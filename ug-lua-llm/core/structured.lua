-- Normalized structured output.
--
-- One JSON Schema, four wire formats. The Responses API wants the format
-- flattened under `text.format`; Chat-Completions-style providers want it
-- wrapped in `response_format.json_schema`; Gemini carries it in
-- `generationConfig.responseSchema` with a JSON mime type; and Claude has no
-- response-format field at all, so the supported route is a forced tool call
-- whose input schema is the schema.
--
-- Every shape below was checked against a live endpoint. Some models refuse
-- structured output entirely, so like reasoning this degrades to an ordinary
-- request rather than failing one that would otherwise work.

local JSON = require "ug-lua-llm.utils.json"

local Structured = {}

-- How each provider carries a schema, and therefore what `capabilities()`
-- should report:
--   responses  - OpenAI Responses API, flattened text.format
--   chat       - response_format.json_schema
--   schema     - Gemini generationConfig.responseSchema
--   tool       - Claude, via a forced tool call
local FORMAT = {
  openai = "responses",
  grok = "chat",
  groq = "chat",
  deepseek = "chat",
  mistral = "chat",
  openrouter = "chat",
  ollama = "chat",
  ["openai-compatible"] = "chat",
  gemini = "schema",
  claude = "tool",
}

local DEFAULT_NAME = "structured_output"

function Structured.format(provider_name)
  return FORMAT[tostring(provider_name or ""):lower()] or false
end

--- Validate and normalize the caller's `json_schema` option.
--- Accepts a bare JSON Schema, or { name, schema, strict, description }.
-- OpenAI's strict mode requires additionalProperties: false on *every* object
-- node, not just the root, and rejects a schema without it. Passing a caller's
-- schema through unchanged meant the obvious schema -- no additionalProperties,
-- because why would you write one -- failed the strict rung, and the ladder
-- then degraded to plain JSON mode, so the error the caller finally saw named
-- a rung they never asked for.
--
-- Objects nested inside `items` are sealed too: a list of records is exactly
-- the shape a one-level pass misses. An explicit `additionalProperties = true`
-- is left alone, because someone who wrote that meant it.
local function seal(node)
  if type(node) ~= "table" then return node end

  local sealed = {}
  for key, value in pairs(node) do
    if type(value) == "table" then
      sealed[key] = seal(value)
    else
      sealed[key] = value
    end
  end

  if sealed.type == "object" or type(sealed.properties) == "table" then
    if sealed.additionalProperties == nil then
      sealed.additionalProperties = false
    end
  end

  return sealed
end

function Structured.spec(value)
  if value == nil then return nil end
  if type(value) ~= "table" then
    return nil, "json_schema must be a table"
  end
  local schema = value.schema or value
  if type(schema) ~= "table" then
    return nil, "json_schema.schema must be a table"
  end
  if schema.type == nil and schema.properties == nil and schema["$ref"] == nil then
    return nil, "json_schema must look like a JSON Schema"
  end
  -- Strict is the point of asking for a schema, so it is the default.
  local strict = value.strict ~= false
  return {
    name = value.name or DEFAULT_NAME,
    description = value.description,
    schema = strict and seal(schema) or schema,
    strict = strict,
  }
end

local function copy(options)
  local result = {}
  for key, value in pairs(options or {}) do result[key] = value end
  return result
end

-- Gemini's responseSchema accepts a restricted OpenAPI subset, not full JSON
-- Schema, and rejects the request outright on an unknown keyword rather than
-- ignoring it. `additionalProperties` alone is enough to fail a schema that
-- every other provider accepts, so translate rather than forward verbatim.
local GEMINI_UNSUPPORTED = {
  additionalProperties = true, ["$schema"] = true, ["$id"] = true,
  ["$defs"] = true, definitions = true, strict = true, default = true,
  examples = true, patternProperties = true, allOf = true, not_ = true,
  ["not"] = true, const = true, title = true,
}

local function gemini_schema(node)
  if type(node) ~= "table" or JSON.is_null(node) then return node end
  local result = {}
  for key, value in pairs(node) do
    if not GEMINI_UNSUPPORTED[key] then
      if type(value) == "table" then
        result[key] = gemini_schema(value)
      else
        result[key] = value
      end
    end
  end
  return result
end

local function with_generation_config(options, fields)
  local next_options = copy(options)
  local request_options = copy(next_options.request_options)
  local generation = copy(request_options.generationConfig)
  for key, value in pairs(fields) do generation[key] = value end
  request_options.generationConfig = generation
  next_options.request_options = request_options
  return next_options
end

--- Ordered attempts, best first, ending with an ordinary request so a model
--- that refuses structured output still answers.
function Structured.attempts(provider_name, spec, options)
  local format = Structured.format(provider_name)
  -- The Responses carrier writes text.format, which a Chat Completions payload
  -- never reads. A caller on the escape hatch had the schema dropped entirely
  -- and was told it applied, because the request succeeded -- it just carried
  -- nothing. Follow the API actually in use.
  if format == "responses" and options and options.api == "chat_completions" then
    format = "chat"
  end
  local unchanged = function() return copy(options) end
  if not spec or format == false then return { unchanged } end

  if format == "responses" then
    return {
      function()
        local next_options = copy(options)
        local text = copy(next_options.text)
        text.format = {
          type = "json_schema",
          name = spec.name,
          schema = spec.schema,
          strict = spec.strict,
        }
        next_options.text = text
        -- The provider also maps response_format into text.format; setting
        -- both would overwrite the flattened shape the API requires.
        next_options.response_format = nil
        return next_options
      end,
      unchanged,
    }
  end

  if format == "chat" then
    return {
      function()
        local next_options = copy(options)
        next_options.response_format = {
          type = "json_schema",
          json_schema = {
            name = spec.name,
            schema = spec.schema,
            strict = spec.strict,
          },
        }
        return next_options
      end,
      -- Models that reject a schema often still honour plain JSON mode.
      function()
        local next_options = copy(options)
        next_options.response_format = { type = "json_object" }
        return next_options
      end,
      unchanged,
    }
  end

  if format == "schema" then
    return {
      function()
        return with_generation_config(options, {
          responseMimeType = "application/json",
          responseSchema = gemini_schema(spec.schema),
        })
      end,
      function()
        return with_generation_config(options, {
          responseMimeType = "application/json",
        })
      end,
      unchanged,
    }
  end

  if format == "tool" then
    return {
      function()
        local next_options = copy(options)
        local request_options = copy(next_options.request_options)
        request_options.tools = {
          {
            name = spec.name,
            description = spec.description or
              "Return the result using this schema.",
            input_schema = spec.schema,
          },
        }
        request_options.tool_choice = { type = "tool", name = spec.name }
        next_options.request_options = request_options
        return next_options
      end,
      unchanged,
    }
  end

  return { unchanged }
end

-- Signatures of a model refusing structured output rather than failing for an
-- unrelated reason.
local REFUSAL_PATTERNS = {
  "response format", "response_format", "json_schema", "json schema",
  "responseschema", "structured output", "does not support",
  "unsupported", "invalid argument",
}

function Structured.refused(err, details)
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

--- Attach `parsed` to a response: the decoded object the schema asked for.
--- Claude answers with a tool call rather than text, so the arguments are the
--- result there; everywhere else the text is the JSON document.
function Structured.attach(result, provider_name)
  if type(result) ~= "table" then return result end
  local format = Structured.format(provider_name)

  if format == "tool" then
    local calls = result.tool_calls
    local first = type(calls) == "table" and calls[1]
    local arguments = first and JSON.value(first.arguments)
    if type(arguments) == "table" then
      result.parsed = arguments
      return result
    end
  end

  local text = JSON.string_value(result.text)
  if text and text ~= "" then
    local ok, decoded = pcall(JSON.decode, text)
    if ok and type(decoded) == "table" then result.parsed = decoded end
  end
  return result
end

return Structured
