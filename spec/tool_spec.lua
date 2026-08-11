local Tool = require("ug-lua-llm.tools.tool")
local Response = require("ug-lua-llm.core.response")

describe("Tool", function()
  describe("new", function()
    it("creates a tool with required fields", function()
      local tool = Tool.new({
        name = "test_tool",
        description = "A test tool",
        parameters = { type = "object" },
      })
      assert.are.equal("test_tool", tool.name)
      assert.are.equal("A test tool", tool.description)
    end)

    it("errors on missing name", function()
      assert.has_error(function()
        Tool.new({ description = "no name" })
      end, "Tool definition missing required field: name")
    end)

    it("errors on missing description", function()
      assert.has_error(function()
        Tool.new({ name = "no_desc" })
      end, "Tool definition missing required field: description")
    end)
  end)

  describe("create_response", function()
    it("creates a tool response", function()
      local resp = Tool.create_response("my_tool", "result data")
      assert.are.equal("my_tool", resp.tool_name)
      assert.are.equal("result data", resp.content)
    end)
  end)

  describe("to_provider_format", function()
    local tools = {
      {
        name = "get_weather",
        description = "Get weather",
        parameters = {
          type = "object",
          properties = {
            location = { type = "string" },
          },
          required = { "location" },
        },
      },
    }

    it("converts to OpenAI format", function()
      local result = Tool.to_provider_format(tools, "openai")
      assert.are.equal(1, #result)
      assert.are.equal("function", result[1].type)
      assert.are.equal("get_weather", result[1]["function"].name)
    end)

    it("converts to Claude format", function()
      local result = Tool.to_provider_format(tools, "claude")
      assert.are.equal(1, #result)
      assert.are.equal("get_weather", result[1].name)
      assert.is_not_nil(result[1].input_schema)
    end)

    it("converts to Grok format (same as OpenAI)", function()
      local result = Tool.to_provider_format(tools, "grok")
      assert.are.equal("function", result[1].type)
    end)

    it("converts to Groq format (same as OpenAI)", function()
      local result = Tool.to_provider_format(tools, "groq")
      assert.are.equal("function", result[1].type)
    end)

    it("converts to OpenRouter format (same as OpenAI)", function()
      local result = Tool.to_provider_format(tools, "openrouter")
      assert.are.equal("function", result[1].type)
    end)

    it("errors on unsupported provider", function()
      assert.has_error(function()
        Tool.to_provider_format(tools, "unknown")
      end)
    end)
  end)

  describe("parse_tool_calls", function()
    it("parses OpenAI tool calls", function()
      local response = {
        choices = {
          {
            message = {
              tool_calls = {
                {
                  id = "call_1",
                  type = "function",
                  ["function"] = {
                    name = "get_weather",
                    arguments = '{"location":"Tokyo"}',
                  },
                },
              },
            },
          },
        },
      }

      local calls = Tool.parse_tool_calls(response, "openai")
      assert.are.equal(1, #calls)
      assert.are.equal("call_1", calls[1].id)
      assert.are.equal("get_weather", calls[1].name)
      assert.are.equal("Tokyo", calls[1].arguments.location)
      assert.are.equal("function", calls[1].type)
      assert.is_not_nil(calls[1].raw)
    end)

    it("parses Claude tool calls", function()
      local response = {
        content = {
          {
            type = "tool_use",
            id = "tool_1",
            name = "get_weather",
            input = { location = "Paris" },
          },
        },
      }

      local calls = Tool.parse_tool_calls(response, "claude")
      assert.are.equal(1, #calls)
      assert.are.equal("tool_1", calls[1].id)
      assert.are.equal("get_weather", calls[1].name)
      assert.are.equal("Paris", calls[1].arguments.location)
    end)

    it("returns empty table when no tool calls present", function()
      local calls = Tool.parse_tool_calls({ choices = { { message = {} } } }, "openai")
      assert.are.equal(0, #calls)
    end)

    it("parses normalized OpenAI Responses tool calls", function()
      local calls = Tool.parse_tool_calls({ tool_calls = {{
        id = "call_2", name = "lookup", arguments = { query = "Lua" },
      }} }, "openai")
      assert.are.equal("lookup", calls[1].name)
      assert.are.equal("Lua", calls[1].arguments.query)
    end)

    it("preserves malformed argument strings for callers to inspect", function()
      local calls = Tool.parse_tool_calls({ choices = {{ message = { tool_calls = {{
        id = "call_3", ["function"] = { name = "lookup", arguments = "{" },
      }} } }} }, "openai-compatible")
      assert.are.equal("{", calls[1].arguments)
    end)

    -- The documented form passes only the response. A normalized response
    -- records its own provider, so the second argument is optional.
    it("infers the provider from a normalized response", function()
      local response = Response.normalize("groq", { choices = {{ message = {
        content = "hi",
        tool_calls = {{ id = "call_4", type = "function", ["function"] = {
          name = "lookup", arguments = '{"query":"Lua"}',
        } }},
      } }} })
      local calls = Tool.parse_tool_calls(response)
      assert.are.equal(1, #calls)
      assert.are.equal("lookup", calls[1].name)
      assert.are.equal("Lua", calls[1].arguments.query)
    end)

    it("infers the provider for a normalized Claude response", function()
      local response = Response.normalize("claude", {
        content = {{ type = "tool_use", id = "call_5", name = "lookup",
                     input = { query = "Lua" } }},
      })
      local calls = Tool.parse_tool_calls(response)
      assert.are.equal("lookup", calls[1].name)
    end)

    it("prefers an explicit provider over the one on the response", function()
      -- Claude-shaped payload mislabelled as groq: the explicit argument has
      -- to win, otherwise it would be parsed with the wrong reader.
      local response = {
        provider = "groq",
        content = {{ type = "tool_use", id = "call_6", name = "lookup",
                     input = { query = "Lua" } }},
      }
      local calls = Tool.parse_tool_calls(response, "claude")
      assert.are.equal(1, #calls)
      assert.are.equal("lookup", calls[1].name)
    end)

    it("reports an unusable provider without crashing on nil", function()
      local ok, err = pcall(Tool.parse_tool_calls, { choices = {} })
      assert.is_false(ok)
      assert.matches("Unsupported provider", tostring(err), 1, true)
      assert.matches("nil", tostring(err), 1, true)
    end)
  end)
end)
