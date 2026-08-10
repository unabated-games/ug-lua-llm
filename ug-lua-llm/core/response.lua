local Response = {}

local function copy(value)
  local result = {}
  for key, item in pairs(value or {}) do result[key] = item end
  return result
end

function Response.normalize(provider, raw)
  if type(raw) ~= "table" then return raw end
  local result = copy(raw)
  result.provider = provider
  result.raw = raw

  if provider == "claude" then
    local text, calls = {}, {}
    for _, block in ipairs(raw.content or {}) do
      if block.type == "text" then text[#text + 1] = block.text or "" end
      if block.type == "tool_use" then
        calls[#calls + 1] = {
          id = block.id, name = block.name, arguments = block.input or {},
        }
      end
    end
    result.text = table.concat(text)
    result.tool_calls = #calls > 0 and calls or nil
    result.finish_reason = raw.stop_reason
    if raw.usage then
      result.usage = {
        prompt_tokens = raw.usage.input_tokens,
        completion_tokens = raw.usage.output_tokens,
        total_tokens = (raw.usage.input_tokens or 0) + (raw.usage.output_tokens or 0),
        raw = raw.usage,
      }
    end
  elseif provider == "gemini" then
    result.text = raw.content or ""
    if raw.usage and raw.usage.total_input_tokens then
      result.usage = {
        prompt_tokens = raw.usage.total_input_tokens,
        completion_tokens = raw.usage.total_output_tokens,
        total_tokens = raw.usage.total_tokens,
        raw = raw.usage,
      }
    end
  else
    local choice = raw.choices and raw.choices[1]
    result.text = choice and choice.message and choice.message.content or
      choice and choice.text or raw.output_text or raw.content or ""
    result.tool_calls = choice and choice.message and choice.message.tool_calls or
      raw.tool_calls
    result.finish_reason = choice and choice.finish_reason or raw.finish_reason
    if raw.usage and raw.usage.input_tokens then
      result.usage = {
        prompt_tokens = raw.usage.input_tokens,
        completion_tokens = raw.usage.output_tokens,
        total_tokens = raw.usage.total_tokens,
        raw = raw.usage,
      }
    end
  end
  return result
end

return Response
