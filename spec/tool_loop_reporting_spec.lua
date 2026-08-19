-- What a caller can see after a tool exchange.
--
-- The turn that finally answers asks for no tools, so a loop that reports only
-- that turn hands back an empty `tool_calls` in exactly the case where tools
-- were used successfully. These assert the accumulated view instead.
local ToolRegistry = require("ug-lua-llm.tools.registry")

-- A client that replies from a script of canned responses.
local function scripted(responses)
  local index = 0
  local calls_made = {}
  local client = {
    provider = { config = { provider_name = "openai", api = "chat_completions" } },
    config = { provider_name = "openai" },
  }
  local function next_response(messages)
    index = index + 1
    calls_made[#calls_made + 1] = messages
    return responses[index]
  end
  client.chat = function(_, messages) return next_response(messages) end
  client.chat_with_tools = function(_, messages) return next_response(messages) end
  client.capabilities = function() return {} end
  return client, calls_made
end

local function call(id, name, args)
  return { id = id, type = "function",
    ["function"] = { name = name, arguments = args } }
end

local function with_tools(...)
  return { text = "", provider = "openai", tool_calls = { ... } }
end

before_each(function()
  ToolRegistry.register("echo", {
    description = "echo", parameters = { type = "object", properties = {} },
    handler = function(args) return { echoed = args.value } end,
  }, true)
  ToolRegistry.register("boom", {
    description = "fails", parameters = { type = "object", properties = {} },
    handler = function() error("handler exploded") end,
  }, true)
end)

describe("tool loop reporting", function()
  it("accumulates every call and result across rounds", function()
    local client = scripted({
      with_tools(call("b", "echo", '{"value":2}')),
      { text = "done", provider = "openai" },
    })
    local first = with_tools(call("a", "echo", '{"value":1}'))

    local final
    ToolRegistry.process_response(client, first, { { role = "user", content = "go" } },
      function(r) final = r end, { tools = {} })

    assert.are.equal("done", final.text)
    -- Two rounds, one call each: visible on the turn that answered, which
    -- asked for nothing itself.
    assert.are.equal(2, final.tool_rounds)
    assert.are.equal(2, #final.tool_calls)
    assert.are.equal(2, #final.tool_results)
    assert.are.equal("echo", final.tool_calls[1].name)
    assert.are.same({ echoed = 1 }, final.tool_results[1].result)
    assert.are.same({ echoed = 2 }, final.tool_results[2].result)
    assert.is_nil(final.tool_rounds_exhausted)
    assert.is_nil(final.tool_pending)
  end)

  it("reports what the cap stopped separately from what ran", function()
    local client = scripted({
      with_tools(call("b", "echo", '{"value":2}')),
      with_tools(call("c", "echo", '{"value":3}')),
    })
    local first = with_tools(call("a", "echo", '{"value":1}'))

    local final
    ToolRegistry.process_response(client, first, { { role = "user", content = "go" } },
      function(r) final = r end, { tools = {}, max_tool_rounds = 2 })

    assert.is_true(final.tool_rounds_exhausted)
    assert.are.equal(2, final.tool_rounds)
    -- Three asked for, two ran, and the difference is handed back rather than
    -- being silently dropped.
    assert.are.equal(3, #final.tool_calls)
    assert.are.equal(2, #final.tool_results)
    assert.are.equal(1, #final.tool_pending)
    assert.are.equal("echo", final.tool_pending[1].name)
  end)

  it("treats a cap of zero as run nothing, report everything asked for", function()
    local client = scripted({})
    local first = with_tools(call("a", "echo", '{"value":1}'))

    local final
    ToolRegistry.process_response(client, first, { { role = "user", content = "go" } },
      function(r) final = r end, { tools = {}, max_tool_rounds = 0 })

    assert.is_true(final.tool_rounds_exhausted)
    assert.are.equal(0, final.tool_rounds)
    assert.are.equal(1, #final.tool_calls)
    assert.are.equal(0, #final.tool_results)
    assert.are.equal(1, #final.tool_pending)
  end)

  it("hands back a conversation that can be continued", function()
    local client = scripted({ { text = "done", provider = "openai" } })
    local original = { { role = "user", content = "go" } }
    local final
    ToolRegistry.process_response(client, with_tools(call("a", "echo", '{"value":1}')),
      original, function(r) final = r end, { tools = {} })

    assert.is_table(final.messages)
    assert.are.equal("user", final.messages[1].role)
    local last = final.messages[#final.messages]
    assert.are.equal("assistant", last.role)
    assert.are.equal("done", last.content)
    -- The caller's own table is never mutated.
    assert.are.equal(1, #original)
  end)

  it("reports each dispatch to on_tool instead of writing to a stream", function()
    local client = scripted({ { text = "done", provider = "openai" } })
    local seen = {}
    ToolRegistry.process_response(client, with_tools(call("a", "echo", '{"value":1}')),
      { { role = "user", content = "go" } }, function() end,
      { tools = {}, on_tool = function(record) seen[#seen + 1] = record end })

    assert.are.equal(1, #seen)
    assert.are.equal("echo", seen[1].name)
    assert.is_true(seen[1].ok)
    assert.are.same({ echoed = 1 }, seen[1].result)
  end)

  it("marks a failed handler without stopping the exchange", function()
    local client = scripted({ { text = "recovered", provider = "openai" } })
    local final
    ToolRegistry.process_response(client, with_tools(call("a", "boom", "{}")),
      { { role = "user", content = "go" } }, function(r) final = r end, { tools = {} })

    assert.are.equal("recovered", final.text)
    assert.is_false(final.tool_results[1].ok)
    assert.is_not_nil(final.tool_results[1].error)
  end)
end)
