local JSON = require "ug-lua-llm.utils.json"

local Response = {}

local function copy(value)
  local result = {}
  for key, item in pairs(value or {}) do result[key] = item end
  return result
end

-- A decoded JSON null is truthy in Lua, so it wins an `a or b or ""` chain and
-- would surface as the backend's sentinel instead of a string. Strip it at
-- every normalized field.
local value = JSON.value
local string_value = JSON.string_value

-- Normalized `text` is contractually a string, never nil and never a sentinel.
local function text_value(...)
  for index = 1, select("#", ...) do
    local candidate = string_value((select(index, ...)))
    if candidate then return candidate end
  end
  return ""
end

-- Reasoning is billed as output but never returned as text, and each provider
-- reports it differently: an explicit count, or only the gap between the total
-- and the parts. Surface one number so callers can see what thinking cost.
local function reasoning_tokens(usage, prompt_tokens, completion_tokens, total)
  local details = usage.completion_tokens_details or usage.output_tokens_details
  local explicit = details and (value(details.reasoning_tokens) or
    value(details.thoughts_tokens))
  explicit = explicit or value(usage.reasoning_tokens) or
    value(usage.thoughtsTokenCount)
  if explicit then return explicit end
  -- Derived only when the provider gives a total that exceeds its own parts.
  if total and prompt_tokens and completion_tokens then
    local gap = total - prompt_tokens - completion_tokens
    if gap > 0 then return gap end
  end
  return nil
end

local function table_value(candidate)
  candidate = value(candidate)
  if type(candidate) == "table" then return candidate end
  return nil
end

function Response.normalize(provider, raw)
  if type(raw) ~= "table" then return raw end
  local result = copy(raw)
  result.provider = provider
  result.raw = raw

  if provider == "claude" then
    local text, calls = {}, {}
    for _, block in ipairs(value(raw.content) or {}) do
      -- A null block.text would abort table.concat with a hard error rather
      -- than merely leaking, so it has to be filtered before collecting.
      if block.type == "text" then text[#text + 1] = string_value(block.text) or "" end
      if block.type == "tool_use" then
        calls[#calls + 1] = {
          id = value(block.id),
          name = value(block.name),
          arguments = table_value(block.input) or {},
        }
      end
    end
    result.text = table.concat(text)
    result.tool_calls = #calls > 0 and calls or nil
    result.finish_reason = string_value(raw.stop_reason)
    local usage = table_value(raw.usage)
    if usage then
      local prompt_tokens = value(usage.input_tokens)
      local completion_tokens = value(usage.output_tokens)
      local total = (prompt_tokens or 0) + (completion_tokens or 0)
      result.usage = {
        prompt_tokens = prompt_tokens,
        completion_tokens = completion_tokens,
        total_tokens = total,
        reasoning_tokens = reasoning_tokens(usage, prompt_tokens,
          completion_tokens, total),
        raw = usage,
      }
    end
  elseif provider == "gemini" then
    result.text = text_value(raw.content)
    local usage = table_value(raw.usage)
    -- The provider normalizes Gemini's usageMetadata to prompt/completion
    -- names, while the Interactions API reports total_input/total_output.
    -- Accepting only the latter meant Gemini usage was never populated.
    local gemini_prompt = usage and
      (value(usage.total_input_tokens) or value(usage.prompt_tokens))
    if usage and gemini_prompt then
      local prompt_tokens = gemini_prompt
      local completion_tokens = value(usage.total_output_tokens) or
        value(usage.completion_tokens)
      local total = value(usage.total_tokens)
      result.usage = {
        prompt_tokens = prompt_tokens,
        completion_tokens = completion_tokens,
        total_tokens = total,
        reasoning_tokens = reasoning_tokens(usage, prompt_tokens,
          completion_tokens, total),
        raw = usage,
      }
    end
  else
    local choice = table_value(raw.choices) and table_value(raw.choices)[1]
    local message = choice and table_value(choice.message)
    result.text = text_value(
      message and message.content,
      choice and choice.text,
      raw.output_text,
      raw.content)
    result.tool_calls = table_value(message and message.tool_calls) or
      table_value(raw.tool_calls)
    result.finish_reason = string_value(choice and choice.finish_reason) or
      string_value(raw.finish_reason)
    local usage = table_value(raw.usage)
    -- Two field namings are in circulation: Responses-style input/output and
    -- Chat-Completions-style prompt/completion. Only the first was recognised,
    -- so most providers' usage was passed through provider-shaped and the
    -- normalized fields were simply absent.
    if usage and (value(usage.input_tokens) or value(usage.prompt_tokens)) then
      local prompt_tokens = value(usage.input_tokens) or value(usage.prompt_tokens)
      local completion_tokens = value(usage.output_tokens) or
        value(usage.completion_tokens)
      local total = value(usage.total_tokens)
      result.usage = {
        prompt_tokens = prompt_tokens,
        completion_tokens = completion_tokens,
        total_tokens = total,
        reasoning_tokens = reasoning_tokens(usage, prompt_tokens,
          completion_tokens, total),
        raw = usage,
      }
    end
  end
  return result
end

return Response
