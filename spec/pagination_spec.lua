local Pagination = require("ug-lua-llm.utils.pagination")

describe("pagination", function()
  it("escapes and orders query parameters", function()
    assert.are.equal("https://example.test/models?after=a%20b&limit=2",
      Pagination.query("https://example.test/models", { limit = 2, after = "a b" }))
  end)

  it("collects OpenAI cursor pages", function()
    local calls = 0
    local items = assert(Pagination.openai(function(url)
      calls = calls + 1
      if calls == 1 then
        assert.matches("limit=1", url, 1, true)
        return { body = { data = {{ id = "one" }}, has_more = true } }
      end
      assert.matches("after=one", url, 1, true)
      return { body = { data = {{ id = "two" }}, has_more = false } }
    end, "https://example.test/models", { page_size = 1 }))
    assert.are.equal(2, #items)
  end)
end)
