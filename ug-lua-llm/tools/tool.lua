local Tool = {}

-- Create a new tool definition
function Tool.new(definition)
  local required_fields = {"name", "description"}

  for _, field in ipairs(required_fields) do
    if not definition[field] then
      error("Tool definition missing required field: " .. field)
    end
  end

  local tool = {
    name = definition.name,
    description = definition.description,
    parameters = definition.parameters or {},
    function_call = definition.function_call,
  }

  return tool
end

-- Create a tool response
function Tool.create_response(tool_name, content)
  return {
    tool_name = tool_name,
    content = content
  }
end

-- Convert a generic tool format to provider-specific format
function Tool.to_provider_format(tools, provider_name)
  if provider_name == "openai" then
    return Tool.to_openai_format(tools)
  elseif provider_name == "claude" then
    return Tool.to_claude_format(tools)
  elseif provider_name == "grok" then
    return Tool.to_grok_format(tools)
  elseif provider_name == "groq" then
    return Tool.to_groq_format(tools)
  elseif provider_name == "openrouter" then
    return Tool.to_openrouter_format(tools)
  else
    error("Unsupported provider for tool format conversion: " .. provider_name)
  end
end

-- Convert to OpenAI tool format
function Tool.to_openai_format(tools)
  local result = {}

  for _, tool in ipairs(tools) do
    -- Convert our internal format to OpenAI's expected format
    local api_tool = {
      type = "function"
    }

    -- Handle the "function" key separately to avoid using reserved keyword
    api_tool["function"] = {
      name = tool.name,
      description = tool.description,
      parameters = tool.parameters
    }

    table.insert(result, api_tool)
  end

  return result
end

-- Convert to Claude tool format
function Tool.to_claude_format(tools)
  local result = {}

  for _, tool in ipairs(tools) do
    table.insert(result, {
      name = tool.name,
      description = tool.description,
      input_schema = {
        type = "object",
        properties = tool.parameters.properties or {},
        required = tool.parameters.required or {}
      }
    })
  end

  return result
end

-- Convert to Grok tool format
function Tool.to_grok_format(tools)
  -- Currently Grok uses a similar format to OpenAI
  return Tool.to_openai_format(tools)
end

-- Convert to Groq tool format
function Tool.to_groq_format(tools)
  -- Currently Groq uses the OpenAI format
  return Tool.to_openai_format(tools)
end

-- Convert to OpenRouter tool format
function Tool.to_openrouter_format(tools)
  -- OpenRouter passes through tool formats based on the requested model
  -- Default to OpenAI format which works with most models
  return Tool.to_openai_format(tools)
end

-- Parse tool calls from provider responses
local OPENAI_TOOL_PROVIDERS = {
  openai = true,
  ["openai-compatible"] = true,
  mistral = true,
  deepseek = true,
  ollama = true,
  grok = true,
  groq = true,
  openrouter = true,
}

function Tool.parse_tool_calls(response, provider_name)
  if OPENAI_TOOL_PROVIDERS[provider_name] then
    return Tool.parse_openai_tool_calls(response)
  elseif provider_name == "claude" then
    return Tool.parse_claude_tool_calls(response)
  elseif provider_name == "gemini" then
    return Tool.parse_gemini_tool_calls(response)
  else
    error("Unsupported provider for tool call parsing: " .. provider_name)
  end
end

local function decode_arguments(arguments)
  if type(arguments) ~= "string" then return arguments or {} end
  local ok, decoded = pcall(require("ug-lua-llm.utils.json").decode, arguments)
  return ok and decoded or arguments
end

local function normalize_tool_call(call)
  local fn = call["function"] or {}
  return {
    id = call.id or "",
    name = call.name or fn.name or "",
    arguments = decode_arguments(call.arguments or call.input or fn.arguments),
    type = call.type == "tool_use" and "function" or call.type or "function",
    raw = call,
  }
end

function Tool.parse_gemini_tool_calls(response)
  local result = {}
  for _, call in ipairs((response and response.tool_calls) or {}) do
    result[#result + 1] = normalize_tool_call(call)
  end
  return result
end

-- Parse OpenAI tool calls
function Tool.parse_openai_tool_calls(response)
  local result = {}
  local calls = response and response.tool_calls
  if not calls and response and response.choices and response.choices[1] and
     response.choices[1].message then
    calls = response.choices[1].message.tool_calls
  end
  for _, call in ipairs(calls or {}) do
    result[#result + 1] = normalize_tool_call(call)
  end
  return result
end

-- Parse Claude tool calls
function Tool.parse_claude_tool_calls(response)
  local result = {}
  if response and response.tool_calls then
    for _, call in ipairs(response.tool_calls) do
      result[#result + 1] = normalize_tool_call(call)
    end
    return result
  end
  for _, content in ipairs((response and response.content) or {}) do
    if content.type == "tool_use" then
      result[#result + 1] = normalize_tool_call(content)
    end
  end
  return result
end

-- Parse Grok tool calls
function Tool.parse_grok_tool_calls(response)
  return Tool.parse_openai_tool_calls(response)
end

-- Parse Groq tool calls
function Tool.parse_groq_tool_calls(response)
  return Tool.parse_openai_tool_calls(response)
end

-- Parse OpenRouter tool calls
function Tool.parse_openrouter_tool_calls(response)
  return Tool.parse_openai_tool_calls(response)
end

return Tool
