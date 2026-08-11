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
      result.usage = {
        prompt_tokens = value(usage.input_tokens),
        completion_tokens = value(usage.output_tokens),
        total_tokens = (value(usage.input_tokens) or 0) + (value(usage.output_tokens) or 0),
        raw = usage,
      }
    end
  elseif provider == "gemini" then
    result.text = text_value(raw.content)
    local usage = table_value(raw.usage)
    if usage and value(usage.total_input_tokens) then
      result.usage = {
        prompt_tokens = value(usage.total_input_tokens),
        completion_tokens = value(usage.total_output_tokens),
        total_tokens = value(usage.total_tokens),
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
    if usage and value(usage.input_tokens) then
      result.usage = {
        prompt_tokens = value(usage.input_tokens),
        completion_tokens = value(usage.output_tokens),
        total_tokens = value(usage.total_tokens),
        raw = usage,
      }
    end
  end
  return result
end

return Response
