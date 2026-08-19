-- Tool Registry Module
--
-- This module provides a way to register, manage, and retrieve tools
-- for use with LLM providers. It allows for creating tool collections
-- that can be easily reused across different LLM requests.
--
-- Usage:
--   local ToolRegistry = require("ug-lua-llm.tools.registry")
--
--   -- Register a tool with its implementation function
--   ToolRegistry.register("get_weather", {
--     description = "Get the current weather for a location",
--     parameters = {
--       type = "object",
--       properties = {
--         location = { type = "string", description = "The city and state" },
--         unit = { type = "string", enum = {"celsius", "fahrenheit"} }
--       },
--       required = {"location"}
--     },
--     handler = function(args)
--       -- Implementation of the weather lookup
--       return { temperature = 22, condition = "sunny", unit = args.unit or "celsius" }
--     end
--   })
--
--   -- Create a collection
--   local weather_tools = ToolRegistry.collection({"get_weather"})
--
--   -- Use with client
--   local response = client:chat_with_tools(messages, weather_tools)
--
--   -- Handle tool calls automatically
--   ToolRegistry.process_response(client, response, messages, function(final_response)
--     print(final_response.content)
--   end)

local json = require("ug-lua-llm.utils.json")
-- Diagnostics go through the logger so a host can route or silence them.
-- print() from inside a library writes to a stream the caller may be using for
-- its own output, and cannot be turned off.
local Logger = require("ug-lua-llm.utils.logger")

local ToolRegistry = {
  _tools = {}, -- Storage for registered tools
  _collections = {}, -- Storage for tool collections
}

-- Register a new tool with the registry
-- @param name (string) Unique name for the tool
-- @param definition (table) Tool definition including handler function
-- @param overwrite (boolean, optional) Whether to overwrite existing tool
-- @return (boolean) Success status
function ToolRegistry.register(name, definition, overwrite)
  -- Check if tool already exists and we're not overwriting
  if ToolRegistry._tools[name] and not overwrite then
    return false, "Tool '" .. name .. "' already exists. Use overwrite=true to replace."
  end

  -- Create a complete tool definition
  local complete_definition = {
    name = name,
    description = definition.description,
    parameters = definition.parameters or {},
    handler = definition.handler -- Store the handler function
  }

  -- Validate the tool definition
  local ok, err = ToolRegistry._validate_tool(complete_definition)
  if not ok then
    return false, err
  end

  -- Store the tool in the registry
  ToolRegistry._tools[name] = complete_definition
  return true
end

-- Register multiple tools at once
-- @param tools (table) A map of tool names to definitions
-- @param overwrite (boolean, optional) Whether to overwrite existing tools
-- @return (boolean) Success status, (string) Error message if failed
function ToolRegistry.register_many(tools, overwrite)
  for name, definition in pairs(tools) do
    local success, err = ToolRegistry.register(name, definition, overwrite)
    if not success then
      return false, "Failed to register tool '" .. name .. "': " .. err
    end
  end
  return true
end

-- Get a registered tool by name
-- @param name (string) The name of the tool to retrieve
-- @return (table) The tool definition
function ToolRegistry.get(name)
  return ToolRegistry._tools[name]
end

-- Get a tool without the handler function (for sending to LLMs)
-- @param name (string) The name of the tool to retrieve
-- @return (table) The tool definition without handler
function ToolRegistry.get_definition(name)
  local tool = ToolRegistry._tools[name]
  if not tool then
    return nil
  end

  -- Create a copy without the handler
  local definition = {
    name = tool.name,
    description = tool.description,
    parameters = tool.parameters
  }

  return definition
end

-- Check if a tool exists in the registry
-- @param name (string) The name of the tool to check
-- @return (boolean) Whether the tool exists
function ToolRegistry.exists(name)
  return ToolRegistry._tools[name] ~= nil
end

-- Unregister a tool from the registry
-- @param name (string) The name of the tool to unregister
-- @return (boolean) Success status
function ToolRegistry.unregister(name)
  if not ToolRegistry._tools[name] then
    return false, "Tool '" .. name .. "' does not exist"
  end

  ToolRegistry._tools[name] = nil
  return true
end

-- List all registered tools
-- @return (table) A list of tool names
function ToolRegistry.list()
  local names = {}
  for name, _ in pairs(ToolRegistry._tools) do
    table.insert(names, name)
  end

  -- Sort alphabetically
  table.sort(names)
  return names
end

-- Create a collection of tools for use with providers (without handlers)
-- @param tool_names (table) A list of tool names to include
-- @return (table) A list of tool definitions ready for the API
function ToolRegistry.collection(tool_names)
  local tools = {}

  for _, name in ipairs(tool_names) do
    local tool = ToolRegistry.get_definition(name)
    if not tool then
      return nil, "Tool '" .. name .. "' not found in registry"
    end

    table.insert(tools, tool)
  end

  return tools
end

-- Create and register a named collection
-- @param collection_name (string) Name for the collection
-- @param tool_names (table) List of tool names to include
-- @param overwrite (boolean, optional) Whether to overwrite existing collection
-- @return (boolean) Success status
function ToolRegistry.create_collection(collection_name, tool_names, overwrite)
  -- Check if collection already exists and we're not overwriting
  if ToolRegistry._collections[collection_name] and not overwrite then
    return false, "Collection '" .. collection_name .. "' already exists. Use overwrite=true to replace."
  end

  -- Validate all tools exist
  for _, name in ipairs(tool_names) do
    if not ToolRegistry.exists(name) then
      return false, "Tool '" .. name .. "' not found in registry"
    end
  end

  -- Store the collection
  ToolRegistry._collections[collection_name] = {
    tool_names = tool_names
  }

  return true
end

-- Get a registered collection by name
-- @param collection_name (string) The name of the collection
-- @return (table) The collection of tool definitions
function ToolRegistry.get_collection(collection_name)
  local collection = ToolRegistry._collections[collection_name]
  if not collection then
    return nil, "Collection '" .. collection_name .. "' not found"
  end

  -- Create the tool definitions
  return ToolRegistry.collection(collection.tool_names)
end

-- List all registered collections
-- @return (table) A list of collection names
function ToolRegistry.list_collections()
  local names = {}
  for name, _ in pairs(ToolRegistry._collections) do
    table.insert(names, name)
  end

  -- Sort alphabetically
  table.sort(names)
  return names
end

-- Get collection details
-- @param collection_name (string) The name of the collection
-- @return (table) Details about the collection
function ToolRegistry.collection_details(collection_name)
  local collection = ToolRegistry._collections[collection_name]
  if not collection then
    return nil, "Collection '" .. collection_name .. "' not found"
  end

  return {
    name = collection_name,
    tool_names = collection.tool_names,
    tool_count = #collection.tool_names
  }
end

-- Execute a tool handler
-- @param tool_name (string) Name of the tool to execute
-- @param args (table) Arguments to pass to the handler
-- @return (table) Result of the handler execution
function ToolRegistry.execute(tool_name, args)
  local tool = ToolRegistry._tools[tool_name]
  if not tool then
    return nil, "Tool '" .. tool_name .. "' not found"
  end

  if not tool.handler or type(tool.handler) ~= "function" then
    return nil, "Tool '" .. tool_name .. "' does not have a handler function"
  end

  -- Execute the handler and return the result
  local success, result = pcall(tool.handler, args)
  if not success then
    return nil, "Error executing tool '" .. tool_name .. "': " .. tostring(result)
  end

  return result
end

-- Process tool calls from an LLM response and normalize into a unified format
-- @param client (table) The LLM client
-- @param response (table) The LLM response
-- @param provider_name (string, optional) The provider name (auto-detected if nil)
-- @return (table) Tool call information in a normalized format
function ToolRegistry.process_tool_calls(client, response, provider_name)
  -- Auto-detect provider if not specified
  if not provider_name then
    -- Safely check client for StreamHelpers
    local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
    provider_name = StreamHelpers.get_provider_type(client)
  end

  -- Provider parsers return one normalized shape.
  local Tool = require("ug-lua-llm.tools.tool")
  return Tool.parse_tool_calls(response, provider_name)
end

-- Process a response and automatically handle tool calls
-- @param client (table) The LLM client
-- @param response (table) The LLM response
-- @param messages (table) The conversation messages so far
-- @param callback (function) Callback for the final response
-- @param options (table, optional) Options for the chat request
-- Default ceiling on tool rounds. High enough for the multi-step shapes that
-- occur in practice, low enough that a model looping on itself stops.
local DEFAULT_MAX_TOOL_ROUNDS = 8

function ToolRegistry.process_response(client, response, messages, callback, options)
  local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
  local provider_name = StreamHelpers.get_provider_type(client)
  options = options or {}
  local max_rounds = tonumber(options.max_tool_rounds) or DEFAULT_MAX_TOOL_ROUNDS

  local current_response = response
  local current_messages = messages
  local rounds = 0

  -- A model may need a second tool once it sees the first result -- look up a
  -- city, then look up its weather. Returning after one round meant the second
  -- request was never made, so those conversations simply stopped.
  while true do
    local tool_calls = ToolRegistry.process_tool_calls(
      client, current_response, provider_name)

    if #tool_calls == 0 then
      callback(current_response)
      return current_response
    end

    if rounds >= max_rounds then
      -- Stop rather than loop forever, and say so instead of passing off a
      -- response whose tool calls were never executed.
      if type(current_response) == "table" then
        current_response.tool_rounds_exhausted = true
        current_response.tool_rounds = rounds
      end
      callback(current_response)
      return current_response
    end
    rounds = rounds + 1

    local tool_results = {}
    for i, call in ipairs(tool_calls) do
      local result, err = ToolRegistry.execute(call.name, call.arguments)
      if err then
        Logger.warn("Tool " .. tostring(call.name) .. " failed: " .. tostring(err))
        result = { error = err }
      end

      local result_str
      if type(result) == "table" then
        result_str = json.encode(result)
      else
        result_str = tostring(result)
      end

      tool_results[i] = {
        id = call.id,
        name = call.name,
        arguments = call.arguments,
        result = result,
        result_str = result_str
      }
    end

    current_messages = ToolRegistry._prepare_tool_response_messages(
      current_messages, tool_results, provider_name, current_response,
      ToolRegistry._uses_responses_api(client, provider_name, options)
    )

    -- Re-offer the tools on the follow-up. Without them the model cannot ask
    -- for a second one however much it needs to, so a multi-step task stops
    -- after the first result and the model apologises instead of continuing.
    local next_response, err, details
    if options.tools then
      next_response, err, details =
        client:chat_with_tools(current_messages, options.tools, options)
    else
      next_response, err, details = client:chat(current_messages, options)
    end
    if not next_response then
      -- Surface the failure rather than handing back a nil response.
      callback(nil, err, details)
      return nil, err, details
    end
    current_response = next_response
  end
end

-- Process a response with tool calls and stream the final response
-- @param client (table) The LLM client
-- @param response (table) The LLM response
-- @param messages (table) The conversation messages so far
-- @param stream_callback (function) Callback for streaming content chunks
-- @param final_callback (function, optional) Callback for the complete final response
-- @param options (table, optional) Options for the chat request
function ToolRegistry.process_response_streaming(client, response, messages, stream_callback, final_callback, options)
  local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")
  local provider_name = StreamHelpers.get_provider_type(client)

  -- Parse tool calls into a normalized format
  local tool_calls = ToolRegistry.process_tool_calls(client, response, provider_name)

  -- No tool calls found
  if #tool_calls == 0 then
    if final_callback then
      final_callback(response)
    end
    return
  end

  -- Process each tool call
  local tool_results = {}
  for i, call in ipairs(tool_calls) do
    -- Execute the tool with normalized arguments
    local result, err = ToolRegistry.execute(call.name, call.arguments)
    if err then
      Logger.warn("Tool call failed: " .. tostring(err))
      result = { error = err }
    end

    -- Format the result
    local result_str
    if type(result) == "table" then
      result_str = json.encode(result)
    else
      result_str = tostring(result)
    end

    -- Store results in a unified format
    tool_results[i] = {
      id = call.id,
      name = call.name,
      arguments = call.arguments,
      result = result,
      result_str = result_str
    }
  end

  -- Prepare messages for the follow-up based on provider
  local updated_messages = ToolRegistry._prepare_tool_response_messages(
    messages, tool_results, provider_name, response,
    ToolRegistry._uses_responses_api(client, provider_name, options)
  )

  -- Use StreamHelpers to create a content-only callback
  local content_callback = StreamHelpers.content_callback(stream_callback)

  -- Track the full response for the final callback
  local full_response = nil

  -- Stream the final response
  local streaming_response = client:stream_chat(updated_messages, function(delta, full)
    -- Pass the content to the user's stream callback via the content_callback
    content_callback(delta, full)

    -- Store the full response for the final callback
    if full then
      full_response = full
    end
  end, options)

  -- Call the final callback if provided
  if final_callback and full_response then
    final_callback(full_response)
  elseif final_callback and streaming_response then
    final_callback(streaming_response)
  end
end

-- Helper function to prepare messages with tool responses based on provider
-- @param messages (table) Original conversation messages
-- @param tool_results (table) Results from tool execution
-- @param provider_name (string) The provider name
-- @return (table) Updated messages with tool responses
-- True when this client talks to OpenAI's Responses API, which is the default
-- and which takes a different shape for tool exchanges than Chat Completions.
function ToolRegistry._uses_responses_api(client, provider_name, options)
  if provider_name ~= "openai" then return false end
  local config = client and client.provider and client.provider.config or {}
  local api = (options and options.api) or config.api or "responses"
  return api == "responses"
end

function ToolRegistry._prepare_tool_response_messages(messages, tool_results, provider_name, assistant_response, uses_responses)
  -- Create a copy of the original messages
  local updated_messages = {}
  for _, msg in ipairs(messages) do
    table.insert(updated_messages, msg)
  end

  -- Add tool responses to messages based on provider format
  if provider_name == "claude" then
    -- Preserve Claude's original tool_use blocks and correlate each result by
    -- tool_use_id. Prose substitutes lose the protocol linkage.
    if assistant_response and assistant_response.content then
      table.insert(updated_messages, {
        role = "assistant",
        content = assistant_response.content,
      })
    end
    local result_blocks = {}
    for _, result in ipairs(tool_results) do
      result_blocks[#result_blocks + 1] = {
        type = "tool_result",
        tool_use_id = result.id,
        content = result.result_str,
      }
    end
    table.insert(updated_messages, { role = "user", content = result_blocks })
  elseif provider_name == "gemini" then
    local call_parts, result_parts = {}, {}
    for _, result in ipairs(tool_results) do
      call_parts[#call_parts + 1] = {
        functionCall = { name = result.name, args = result.arguments or {} },
      }
      result_parts[#result_parts + 1] = {
        functionResponse = {
          name = result.name,
          response = type(result.result) == "table" and result.result or
            { result = result.result },
        },
      }
    end
    table.insert(updated_messages, { role = "assistant", content = call_parts })
    table.insert(updated_messages, { role = "user", content = result_parts })
  else
    -- OpenAI/compatible format
    -- Add the assistant message with tool calls
    if uses_responses then
      -- The Responses API takes tool exchanges as typed input items, not as an
      -- assistant message carrying tool_calls. Sending the Chat Completions
      -- shape was rejected outright ("Unknown parameter: input[N].tool_calls"),
      -- so the follow-up request never succeeded and no final answer was ever
      -- produced.
      for _, result in ipairs(tool_results) do
        table.insert(updated_messages, {
          type = "function_call",
          call_id = result.id,
          name = result.name,
          arguments = type(result.arguments) == "table"
            and json.encode(result.arguments)
            or tostring(result.arguments or "{}"),
        })
        table.insert(updated_messages, {
          type = "function_call_output",
          call_id = result.id,
          output = result.result_str,
        })
      end
      return updated_messages
    end

    local assistant_msg = {
      role = "assistant",
      content = "",
      tool_calls = {}
    }

    -- Add each tool call
    for _, result in ipairs(tool_results) do
      table.insert(assistant_msg.tool_calls, {
        id = result.id,
        type = "function",
        ["function"] = {
          name = result.name,
          arguments = type(result.arguments) == "table"
            and json.encode(result.arguments)
            or tostring(result.arguments)
        }
      })
    end

    -- Add the assistant message
    table.insert(updated_messages, assistant_msg)

    -- Add each tool result
    for _, result in ipairs(tool_results) do
      table.insert(updated_messages, {
        role = "tool",
        tool_call_id = result.id,
        content = result.result_str
      })
    end
  end

  return updated_messages
end

-- Validate a tool definition
-- @param tool (table) The tool definition to validate
-- @return (boolean) Whether the tool is valid, (string) Error message if invalid
function ToolRegistry._validate_tool(tool)
  -- Check required fields
  local required_fields = {"name", "description"}
  for _, field in ipairs(required_fields) do
    if not tool[field] then
      return false, "Tool definition missing required field: " .. field
    end
  end

  -- Validate parameters if present
  if tool.parameters and type(tool.parameters) == "table" then
    -- Basic JSON Schema validation could be added here
    -- For now, we just ensure parameters has the right structure
    if tool.parameters.properties and type(tool.parameters.properties) ~= "table" then
      return false, "Tool parameters.properties must be a table"
    end
  end

  -- Ensure handler is a function if provided
  if tool.handler ~= nil and type(tool.handler) ~= "function" then
    return false, "Tool handler must be a function"
  end

  return true
end

-- Extract content from a response in a provider-agnostic way
-- @param response (table) The response from the model
-- @return (string) The extracted content
function ToolRegistry.extract_content(response)
  local content

  -- Handle different provider response formats
  if response.text then
    content = response.text
  elseif response.content then
    -- Claude format
    content = response.content
  elseif response.choices and response.choices[1] then
    -- OpenAI format
    if response.choices[1].message and response.choices[1].message.content then
      content = response.choices[1].message.content
    elseif response.choices[1].text then
      -- Legacy completion format
      content = response.choices[1].text
    end
  end

  if type(content) == "table" then
    local parts = {}
    for _, block in ipairs(content) do
      if block.type == "text" then parts[#parts + 1] = block.text or "" end
    end
    return table.concat(parts)
  end
  return content or ""
end

-- Include standard tool definitions with working implementations
local function get_weather_handler(args)
  -- This is a mock implementation - in a real app, you'd call a weather API
  local location = args.location or "Unknown"
  local unit = args.unit or "celsius"

  -- Simulate different weather for different locations
  local temp, condition
  if location:lower():find("paris") then
    temp = 22
    condition = "sunny"
  elseif location:lower():find("london") then
    temp = 15
    condition = "rainy"
  elseif location:lower():find("new york") then
    temp = 18
    condition = "cloudy"
  else
    temp = 20
    condition = "clear"
  end

  -- Convert to fahrenheit if requested
  if unit == "fahrenheit" then
    temp = temp * 9/5 + 32
  end

  return {
    temperature = temp,
    unit = unit,
    condition = condition,
    location = location
  }
end

local function calculator_handler(args)
  local expression = args.expression

  -- Security: Basic validation to prevent code injection
  if not expression:match("^[0-9%+%-%*/%(%). ]+$") then
    return { error = "Invalid expression. Only numbers and basic operators (+,-,*,/,()) are allowed." }
  end

  -- Create a safe environment for evaluation
  local env = {}
  local result, err
  if _VERSION == "Lua 5.1" then
    result, err = loadstring("return " .. expression, "expression")
    if result then setfenv(result, env) end
  else
    result, err = load("return " .. expression, "expression", "t", env)
  end

  if not result then
    return { error = "Failed to parse expression: " .. tostring(err) }
  end

  local success, value = pcall(result)
  if not success then
    return { error = "Error calculating result: " .. tostring(value) }
  end

  return {
    result = value,
    expression = expression
  }
end

-- Standard tools with handlers
ToolRegistry.standard_tools = {
  get_weather = {
    description = "Get the current weather for a location",
    parameters = {
      type = "object",
      properties = {
        location = {
          type = "string",
          description = "The city and state, e.g. San Francisco, CA"
        },
        unit = {
          type = "string",
          enum = {"celsius", "fahrenheit"},
          description = "The unit of temperature to use"
        }
      },
      required = {"location"}
    },
    handler = get_weather_handler
  },

  calculator = {
    description = "Perform a calculation",
    parameters = {
      type = "object",
      properties = {
        expression = {
          type = "string",
          description = "The mathematical expression to evaluate (e.g. '2 + 2 * 3')"
        }
      },
      required = {"expression"}
    },
    handler = calculator_handler
  }
}

--- Register the bundled example tools and their collections.
---
--- These used to be registered when the module loaded, so every consumer got a
--- `get_weather` and a `calculator` they never asked for, in a registry shared
--- across the whole process. They are demonstrations, so opting in is now
--- explicit; call this if you were relying on them being present.
function ToolRegistry.register_standard_tools(overwrite)
  for name, definition in pairs(ToolRegistry.standard_tools) do
    ToolRegistry.register(name, definition, overwrite)
  end
  ToolRegistry.create_collection("standard", {"get_weather", "calculator"})
  ToolRegistry.create_collection("weather", {"get_weather"})
  ToolRegistry.create_collection("calculator", {"calculator"})
  return true
end

return ToolRegistry
