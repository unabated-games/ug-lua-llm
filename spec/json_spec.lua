local json = require("ug-lua-llm.utils.json")

describe("JSON adapter", function()
  it("exposes the selected backend", function()
    assert.is_true(json.backend == "cjson" or json.backend == "dkjson")
  end)

  it("round trips objects and arrays", function()
    local decoded = json.decode(json.encode({ name = "test", values = { 1, 2 } }))
    assert.are.equal("test", decoded.name)
    assert.are.same({ 1, 2 }, decoded.values)
  end)

  it("preserves cjson empty-table object semantics", function()
    assert.are.equal("{}", json.encode({}))
    assert.matches('"properties":{}', json.encode({ properties = {} }), 1, true)
  end)

  it("raises an error for malformed JSON", function()
    assert.has_error(function() json.decode("{invalid") end)
  end)
end)
