-- Example showing how to use the Tool Registry
--
-- This example demonstrates:
-- 1. Registering custom tools with handler functions
-- 2. Using pre-defined tool collections
-- 3. Creating custom tool collections
-- 4. Automatic processing of tool calls
--
-- Usage: lua5.4 examples/tool_registry_example.lua [--provider openai|claude|groq|grok|openrouter] [--model modelname]

package.path = package.path .. ";../?.lua;./?.lua"

local ToolRegistry = require "ug-lua-llm.tools.registry"

-- The bundled example tools (get_weather, calculator) are opt-in, so a library
-- consumer never inherits tools they did not define.
ToolRegistry.register_standard_tools()
local StreamHelpers = require "ug-lua-llm.utils.stream_helpers"
local ClientFactory = require "examples.helpers.client_factory"
local json = require "cjson"

-- Create a client using the ClientFactory
local result = ClientFactory.create_client()
local client = result.client
local provider_name = result.provider
local model_name = result.model

print("Using " .. provider_name .. " with model: " .. model_name)

-- Define and register a custom tool for database queries
ToolRegistry.register("query_database", {
  description = "Query a database for information",
  parameters = {
    type = "object",
    properties = {
      table = {
        type = "string",
        description = "The table to query"
      },
      field = {
        type = "string",
        description = "The field to retrieve"
      },
      where = {
        type = "string",
        description = "The condition to filter by"
      }
    },
    required = {"table", "field"}
  },
  -- Handler function to execute when the tool is called
  handler = function(args)
    -- Simulate a database query
    print("DB Query received: " .. json.encode(args))
    
    -- This is a mock implementation
    local data = {
      users = {
        {id = 1, name = "Alice", age = 30, role = "admin"},
        {id = 2, name = "Bob", age = 25, role = "user"},
        {id = 3, name = "Charlie", age = 35, role = "user"}
      },
      products = {
        {id = 1, name = "Laptop", price = 1200, stock = 10},
        {id = 2, name = "Phone", price = 800, stock = 20},
        {id = 3, name = "Tablet", price = 500, stock = 15}
      }
    }
    
    -- Extract parameters
    local table_name = args.table
    local field = args.field
    local where_condition = args.where
    
    -- Check if the table exists
    if not data[table_name] then
      return {error = "Table '" .. table_name .. "' not found"}
    end
    
    -- Filter results if a where condition is provided
    local results = {}
    for _, row in ipairs(data[table_name]) do
      local match = true
      
      -- Simple where parser for conditions like "name = Alice" or "price > 700"
      if where_condition then
        local field_name, op, value = where_condition:match("([%w_]+)%s*([=<>]+)%s*(.+)")
        
        if field_name and op and value then
          -- Remove quotes if present
          value = value:gsub("^'(.*)'$", "%1"):gsub('^"(.*)"$', "%1")
          
          -- Try to convert to number if possible
          local num_value = tonumber(value)
          if num_value then value = num_value end
          
          -- Check condition
          if op == "=" and row[field_name] ~= value then
            match = false
          elseif op == ">" and (not tonumber(row[field_name]) or tonumber(row[field_name]) <= value) then
            match = false
          elseif op == "<" and (not tonumber(row[field_name]) or tonumber(row[field_name]) >= value) then
            match = false
          end
        end
      end
      
      -- Add matching row to results
      if match then
        if field == "*" then
          table.insert(results, row)
        else
          table.insert(results, {[field] = row[field]})
        end
      end
    end
    
    return {
      query = {
        table = table_name,
        field = field,
        where = where_condition
      },
      results = results,
      count = #results
    }
  end
})

-- Create a custom collection with our database tool and the built-in weather tool
local success = ToolRegistry.create_collection("my_tools", {"query_database", "get_weather"})
if not success then
  print("Failed to create tool collection")
  os.exit(1)
end

-- List available tools and collections
print("\n--- Available Tools ---")
local tools = ToolRegistry.list()
for _, name in ipairs(tools) do
  print("- " .. name)
end

print("\n--- Available Collections ---")
local collections = ToolRegistry.list_collections()
for _, name in ipairs(collections) do
  local details = ToolRegistry.collection_details(name)
  print("- " .. name .. " (" .. details.tool_count .. " tools)")
  for i, tool_name in ipairs(details.tool_names) do
    print("  " .. i .. ". " .. tool_name)
  end
end

-- Example 1: Using built-in weather tool with automatic processing
print("\n\n--- Example 1: Weather Tool ---")
local messages = {
  { role = "system", content = "You are a helpful assistant with access to tools." },
  { role = "user", content = "What's the weather like in Paris right now? Use celsius." }
}

-- Get the weather tools collection
local weather_tools = ToolRegistry.get_collection("weather")

-- Basic demonstration - first with streaming to show the model invoking tools
print("\nStreaming response (showing tool call detection):")
client:stream_chat_with_tools(messages, weather_tools, 
  StreamHelpers.tool_call_detector(
    -- Tool call detection callback
    function()
      io.write("\n[Tool call detected]\n")
      io.flush()
    end,
    -- Content callback for non-tool content
    function(content)
      io.write(content)
      io.flush()
    end
  )
)

-- Now with automatic tool execution
print("\n\nUsing automatic tool execution:")
local response = client:chat_with_tools(messages, weather_tools)

-- Process the response with the tool registry
print("\nProcessing tool calls automatically...")
local tool_calls = ToolRegistry.process_tool_calls(client, response)
if #tool_calls > 0 then
  print("Found " .. #tool_calls .. " tool call(s):")
  for i, call in ipairs(tool_calls) do
    -- Now using the normalized tool call format
    print("Tool " .. i .. ": " .. call.name)
    print("Arguments: " .. json.encode(call.arguments))
    
    -- Execute tool manually to show results
    local execution_result, err = ToolRegistry.execute(call.name, call.arguments)
    if execution_result then
      print("Result: " .. json.encode(execution_result))
    else
      print("Error: " .. (err or "Unknown error"))
    end
  end
end

ToolRegistry.process_response(client, response, messages, function(final_response)
  print("\nFinal response after tool execution:")
  
  -- Use the provider-agnostic content extraction
  local content = ToolRegistry.extract_content(final_response)
  print("Content: " .. content)
end)

-- Example 2: Using custom database query tool
print("\n\n--- Example 2: Database Query Tool ---")
local db_messages = {
  { role = "system", content = "You are a helpful assistant with access to tools. You can query our database using the query_database tool." },
  { role = "user", content = "Can you find all products that cost more than $700?" }
}

-- Get the custom tools collection
local my_tools = ToolRegistry.get_collection("my_tools")

-- Stream the response to show tool detection
print("\nStreaming response (showing tool call detection):")
client:stream_chat_with_tools(db_messages, my_tools, 
  StreamHelpers.tool_call_detector(
    -- Tool call detection callback
    function()
      io.write("\n[Tool call detected]\n")
      io.flush()
    end,
    -- Content callback for non-tool content
    function(content)
      io.write(content)
      io.flush()
    end
  )
)

-- Automatic execution
print("\n\nUsing automatic tool execution:")
local db_response = client:chat_with_tools(db_messages, my_tools)

-- Process the response with the tool registry
print("\nProcessing tool calls automatically...")
local db_tool_calls = ToolRegistry.process_tool_calls(client, db_response)
if #db_tool_calls > 0 then
  print("Found " .. #db_tool_calls .. " tool call(s):")
  for i, call in ipairs(db_tool_calls) do
    -- Now using the normalized tool call format
    print("Tool " .. i .. ": " .. call.name)
    print("Arguments: " .. json.encode(call.arguments))
    
    -- Execute tool manually to show results
    local execution_result, err = ToolRegistry.execute(call.name, call.arguments)
    if execution_result then
      print("Result: " .. json.encode(execution_result))
    else
      print("Error: " .. (err or "Unknown error"))
    end
  end
end

ToolRegistry.process_response(client, db_response, db_messages, function(final_response)
  print("\nFinal response after tool execution:")
  
  -- Use the provider-agnostic content extraction
  local content = ToolRegistry.extract_content(final_response)
  print("Content: " .. content)
end)

-- Example 3: Using the calculator tool
print("\n\n--- Example 3: Calculator Tool ---")
local calc_messages = {
  { role = "system", content = "You are a helpful assistant with access to tools." },
  { role = "user", content = "What is 354 * 879 divided by 3?" }
}

-- Get the calculator tools collection
local calc_tools = ToolRegistry.get_collection("calculator")

-- Stream the response to show tool detection
print("\nStreaming response (showing tool call detection):")
client:stream_chat_with_tools(calc_messages, calc_tools, 
  StreamHelpers.tool_call_detector(
    -- Tool call detection callback
    function()
      io.write("\n[Tool call detected]\n")
      io.flush()
    end,
    -- Content callback for non-tool content
    function(content)
      io.write(content)
      io.flush()
    end
  )
)

-- Automatic execution
print("\n\nUsing automatic tool execution:")
local calc_response = client:chat_with_tools(calc_messages, calc_tools)

-- Process the response with the tool registry
print("\nProcessing tool calls automatically...")
local calc_tool_calls = ToolRegistry.process_tool_calls(client, calc_response)
if #calc_tool_calls > 0 then
  print("Found " .. #calc_tool_calls .. " tool call(s):")
  for i, call in ipairs(calc_tool_calls) do
    -- Now using the normalized tool call format
    print("Tool " .. i .. ": " .. call.name)
    print("Arguments: " .. json.encode(call.arguments))
    
    -- Execute tool manually to show results
    local execution_result, err = ToolRegistry.execute(call.name, call.arguments)
    if execution_result then
      print("Result: " .. json.encode(execution_result))
    else
      print("Error: " .. (err or "Unknown error"))
    end
  end
end

ToolRegistry.process_response(client, calc_response, calc_messages, function(final_response)
  print("\nFinal response after tool execution:")
  
  -- Use the provider-agnostic content extraction
  local content = ToolRegistry.extract_content(final_response)
  print("Content: " .. content)
end)

print("\n\n--- Example Usage in Your App ---")
print([[
-- Register your tools:
ToolRegistry.register("my_custom_tool", {
  description = "Description of what the tool does",
  parameters = {
    type = "object",
    properties = {
      param1 = { type = "string", description = "Parameter description" }
    },
    required = {"param1"}
  },
  handler = function(args)
    -- Your tool implementation
    local result = doSomethingWith(args.param1)
    return { result = result }
  end
})

-- Create a collection:
ToolRegistry.create_collection("app_tools", {"my_custom_tool", "get_weather"})

-- Use in chat:
local tools = ToolRegistry.get_collection("app_tools")
local response = client:chat_with_tools(messages, tools)

-- Process tool calls automatically:
ToolRegistry.process_response(client, response, messages, function(final_response)
  -- Handle the final response after tool execution
  displayToUser(final_response.text or ToolRegistry.extract_content(final_response))
end)
]])
