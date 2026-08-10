local Tool = require("ug-lua-llm.tools.tool")
local ToolRegistry = require("ug-lua-llm.tools.registry")
local StreamHelpers = require("ug-lua-llm.utils.stream_helpers")

describe("provider contracts", function()
  it("detects Gemini explicitly after moving authentication to a header", function()
    local client = { provider = {
      config = { provider_name = "gemini", base_url = "https://generativelanguage.googleapis.com/v1beta" },
      http = { headers = { ["x-goog-api-key"] = "secret" } },
    } }
    assert.are.equal("gemini", StreamHelpers.get_provider_type(client))
  end)

  it("parses normalized Gemini function calls", function()
    local calls = Tool.parse_tool_calls({ tool_calls = {{
      id = "call_1", ["function"] = { name = "weather", arguments = '{"city":"Paris"}' },
    }} }, "gemini")
    assert.are.equal("weather", calls[1].name)
    assert.are.equal("Paris", calls[1].arguments.city)
  end)

  it("builds native Gemini function response turns", function()
    local messages = ToolRegistry._prepare_tool_response_messages({}, {{
      id = "call_1", name = "weather", arguments = { city = "Paris" },
      result = { temp = 22 }, result_str = '{"temp":22}',
    }}, "gemini")
    assert.are.equal("weather", messages[1].content[1].functionCall.name)
    assert.are.equal(22, messages[2].content[1].functionResponse.response.temp)
  end)
end)
