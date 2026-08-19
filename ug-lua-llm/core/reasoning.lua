-- Normalized reasoning control.
--
-- Providers express "think less" in unrelated ways: an effort string, a token
-- budget, an opt-in block, or a different model entirely. Some reject the
-- option outright on models that do not reason. This module translates one
-- `reasoning` option into whatever a provider understands, and describes an
-- ordered set of attempts so a request is never turned into an error by asking
-- for something the model cannot do.
--
-- The mappings below were measured against live endpoints rather than taken
-- from documentation, because several providers accept a field and ignore it,
-- or reject it with a 400 that names the field.

local Reasoning = {}

-- How each provider expresses control, and therefore what a caller can expect:
--   effort  - an effort string, and "none" usually disables reasoning
--   budget  - a token budget; may refuse zero, so cannot always be disabled
--   opt_in  - does not reason unless asked, so "off" is the default
--   false   - no control; the model reasons or does not, by its own design
local CONTROL = {
  openai = "effort",
  grok = "effort",
  groq = "effort",
  deepseek = "effort",
  mistral = "effort",
  openrouter = "effort",
  ollama = "effort",
  ["openai-compatible"] = "effort",
  claude = "opt_in",
  gemini = "budget",
}

local LEVELS = { none = true, low = true, medium = true, high = true }

-- Gemini counts reasoning in tokens. Zero is refused by some models, so the
-- "none" attempt falls back to the smallest budget they do accept.
local GEMINI_BUDGET = { none = 0, low = 512, medium = 2048, high = 8192 }
local GEMINI_MINIMUM = 1

-- Claude reasons only when asked, and requires max_tokens above the budget.
local CLAUDE_BUDGET = { low = 1024, medium = 4096, high = 16384 }

-- Current models express thinking as an effort level instead, and report which
-- levels they accept in their capability metadata (low/medium/high/xhigh/max).
local CLAUDE_EFFORT = { low = "low", medium = "medium", high = "high" }

--- Normalize the caller's `reasoning` option to a level, or nil when unset.
--- Accepts false/"none" to minimize, true for a middling default, or a level.
function Reasoning.level(value)
  if value == nil then return nil end
  if value == false then return "none" end
  if value == true then return "medium" end
  if type(value) == "string" and LEVELS[value:lower()] then
    return value:lower()
  end
  return nil, "reasoning must be a boolean or one of: none, low, medium, high"
end

--- What kind of control a provider offers, for `capabilities()`.
function Reasoning.control(provider_name)
  return CONTROL[tostring(provider_name or ""):lower()] or false
end

local function copy(options)
  local result = {}
  for key, value in pairs(options or {}) do result[key] = value end
  return result
end

-- Gemini's budget lives inside a container the provider also generates, so it
-- goes through request_options, whose nested tables are merged rather than
-- replacing what the provider builds.
local function with_gemini_budget(options, budget)
  local next_options = copy(options)
  local request_options = copy(next_options.request_options)
  local generation = copy(request_options.generationConfig)
  generation.thinkingConfig = { thinkingBudget = budget }
  request_options.generationConfig = generation
  next_options.request_options = request_options
  return next_options
end

--- Ordered attempts for a reasoning level, best first. Each entry returns a
--- fresh options table. The final entry always sends no reasoning control at
--- all, so a provider that refuses the option still gets a working request.
function Reasoning.attempts(provider_name, level, options)
  local control = Reasoning.control(provider_name)
  local unchanged = function() return copy(options) end

  if not level or control == false then return { unchanged } end

  if control == "effort" then
    return {
      function()
        local next_options = copy(options)
        next_options.reasoning_effort = level
        return next_options
      end,
      unchanged,
    }
  end

  if control == "budget" then
    local budget = GEMINI_BUDGET[level]
    local list = { function() return with_gemini_budget(options, budget) end }
    if budget == 0 then
      -- Models that refuse a zero budget still accept the smallest positive
      -- one, which is as close to off as they allow.
      list[#list + 1] = function()
        return with_gemini_budget(options, GEMINI_MINIMUM)
      end
    end
    list[#list + 1] = unchanged
    return list
  end

  if control == "opt_in" then
    if level == "none" then
      -- Not asking is the way to turn it off.
      return {
        function()
          local next_options = copy(options)
          next_options.thinking = nil
          next_options.thinking_budget = nil
          return next_options
        end,
      }
    end
    -- Two spellings are in circulation and the newer models accept only the
    -- newer one: `thinking = { type = "enabled", budget_tokens = N }` is
    -- rejected by every current-generation model with "Use
    -- 'thinking.type.adaptive' and 'output_config.effort'". Effort is tried
    -- first because it is what the models list reports as supported, and the
    -- budget form is kept as the next rung for the older models that still
    -- take it -- so neither generation is left without a control.
    return {
      function()
        local next_options = copy(options)
        local output_config = copy(next_options.output_config)
        output_config.effort = output_config.effort or CLAUDE_EFFORT[level]
        next_options.output_config = output_config
        return next_options
      end,
      function()
        local next_options = copy(options)
        local budget = CLAUDE_BUDGET[level]
        next_options.thinking = true
        next_options.thinking_budget = next_options.thinking_budget or budget
        -- Thinking is spent from max_tokens, so the ceiling has to clear it.
        local minimum = budget + 1024
        if (tonumber(next_options.max_tokens) or 0) <= budget then
          next_options.max_tokens = minimum
        end
        return next_options
      end,
      unchanged,
    }
  end

  return { unchanged }
end

--- Whether an attempt actually carried the control the caller asked for.
--- Lives here rather than at the call site because it is a fact about how the
--- ladder is built: a provider with no control has one attempt that sends
--- nothing, so a bare index test reports a request that never mentioned
--- reasoning as compliance.
function Reasoning.applied(provider_name, index)
  return Reasoning.control(provider_name) ~= false and index == 1
end

-- Signatures of a provider refusing the control itself, rather than failing
-- for an unrelated reason. Matched conservatively: an unrelated 400 must not
-- trigger a silent retry that hides it.
local REFUSAL_PATTERNS = {
  "reasoning_effort", "reasoning effort", "reasoning",
  "thinking", "thinkingbudget", "thinking_budget",
  "unsupported value", "invalid argument",
}

--- True when a failure looks like the provider rejecting the reasoning
--- control, so the next attempt is worth making.
function Reasoning.refused(err, details)
  local status = details and details.status
  -- A provider refusing a field always says so with a 4xx. Without a status
  -- this is a transport or timeout failure, and matching its message would let
  -- an unrelated error be retried silently as though it were a refusal.
  if type(status) ~= "number" or status < 400 or status >= 500 then
    return false
  end
  local text = tostring(err or ""):lower()
  for _, pattern in ipairs(REFUSAL_PATTERNS) do
    if text:find(pattern, 1, true) then return true end
  end
  return false
end

return Reasoning
