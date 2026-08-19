describe("ToolRegistry", function()
  local ToolRegistry

  before_each(function()
    -- Reload the module fresh for each test to avoid state leakage.
    -- busted caches modules, so we clear the package.loaded entry first.
    package.loaded["ug-lua-llm.tools.registry"] = nil
    package.loaded["ug-lua-llm.tools.tool"] = nil
    ToolRegistry = require("ug-lua-llm.tools.registry")
  end)

  describe("register / get / exists", function()
    it("registers and retrieves a tool", function()
      local ok = ToolRegistry.register("my_tool", {
        description = "A tool",
        parameters = { type = "object", properties = {} },
        handler = function(args) return { ok = true } end,
      })
      assert.is_true(ok)
      assert.is_true(ToolRegistry.exists("my_tool"))

      local tool = ToolRegistry.get("my_tool")
      assert.are.equal("my_tool", tool.name)
    end)

    it("prevents duplicate registration without overwrite", function()
      ToolRegistry.register("dup", { description = "first" })
      local ok, err = ToolRegistry.register("dup", { description = "second" })
      assert.is_false(ok)
      assert.truthy(err:match("already exists"))
    end)

    it("allows overwrite when requested", function()
      ToolRegistry.register("dup", { description = "first" })
      local ok = ToolRegistry.register("dup", { description = "second" }, true)
      assert.is_true(ok)
      assert.are.equal("second", ToolRegistry.get("dup").description)
    end)
  end)

  describe("get_definition", function()
    it("returns tool without handler", function()
      ToolRegistry.register("def_test", {
        description = "test",
        handler = function() end,
      })
      local def = ToolRegistry.get_definition("def_test")
      assert.are.equal("def_test", def.name)
      assert.is_nil(def.handler)
    end)

    it("returns nil for unknown tool", function()
      assert.is_nil(ToolRegistry.get_definition("nonexistent"))
    end)
  end)

  describe("unregister", function()
    it("removes a registered tool", function()
      ToolRegistry.register("remove_me", { description = "bye" })
      assert.is_true(ToolRegistry.exists("remove_me"))
      ToolRegistry.unregister("remove_me")
      assert.is_false(ToolRegistry.exists("remove_me"))
    end)

    it("returns false for unknown tool", function()
      local ok, _err = ToolRegistry.unregister("ghost")
      assert.is_false(ok)
    end)
  end)

  describe("list", function()
    it("returns sorted list of tool names", function()
      -- The bundled example tools are opt-in now, so a fresh registry starts
      -- empty rather than carrying tools the consumer never defined.
      ToolRegistry.register_standard_tools(true)
      local names = ToolRegistry.list()
      assert.truthy(#names >= 2)
      for i = 2, #names do
        assert.truthy(names[i] >= names[i - 1])
      end
    end)

    it("starts empty until the example tools are asked for", function()
      assert.is_false(ToolRegistry.exists("calculator"))
    end)
  end)

  describe("collection", function()
    it("creates a list of tool definitions", function()
      ToolRegistry.register_standard_tools(true)
      local tools, err = ToolRegistry.collection({ "get_weather", "calculator" })
      assert.is_nil(err)
      assert.are.equal(2, #tools)
    end)

    it("returns error for unknown tool", function()
      local tools, err = ToolRegistry.collection({ "nonexistent" })
      assert.is_nil(tools)
      assert.truthy(err:match("not found"))
    end)
  end)

  describe("execute", function()
    it("executes a tool handler", function()
      ToolRegistry.register("adder", {
        description = "adds numbers",
        handler = function(args) return args.a + args.b end,
      }, true)
      local result = ToolRegistry.execute("adder", { a = 2, b = 3 })
      assert.are.equal(5, result)
    end)

    it("returns error for unknown tool", function()
      local result, err = ToolRegistry.execute("missing", {})
      assert.is_nil(result)
      assert.truthy(err:match("not found"))
    end)

    it("catches errors in handler", function()
      ToolRegistry.register("bad", {
        description = "errors",
        handler = function() error("boom") end,
      }, true)
      local result, err = ToolRegistry.execute("bad", {})
      assert.is_nil(result)
      assert.truthy(err:match("boom"))
    end)
  end)

  describe("extract_content", function()
    it("extracts from Claude format", function()
      local content = ToolRegistry.extract_content({ content = "hello claude" })
      assert.are.equal("hello claude", content)
    end)

    it("extracts from OpenAI format", function()
      local content = ToolRegistry.extract_content({
        choices = { { message = { content = "hello openai" } } },
      })
      assert.are.equal("hello openai", content)
    end)

    it("returns empty string when nothing found", function()
      local content = ToolRegistry.extract_content({})
      assert.are.equal("", content)
    end)
  end)

  describe("Claude tool results", function()
    it("preserves tool_use blocks and correlates native tool_result blocks", function()
      local assistant = { content = {
        { type = "tool_use", id = "tool_1", name = "weather", input = { city = "Paris" } },
      } }
      local messages = ToolRegistry._prepare_tool_response_messages(
        { { role = "user", content = "Weather?" } },
        { { id = "tool_1", name = "weather", result_str = '{"temp":22}' } },
        "claude", assistant)
      assert.are.equal("assistant", messages[2].role)
      assert.are.equal("tool_use", messages[2].content[1].type)
      assert.are.equal("tool_result", messages[3].content[1].type)
      assert.are.equal("tool_1", messages[3].content[1].tool_use_id)
    end)
  end)
end)
