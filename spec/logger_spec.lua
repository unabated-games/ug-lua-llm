local Logger = require("ug-lua-llm.utils.logger")

describe("Logger", function()
  local captured = {}

  before_each(function()
    captured = {}
    Logger.set_output(function(msg) table.insert(captured, msg) end)
    Logger.set_redact_payloads(true)
  end)

  after_each(function()
    Logger.disable()
    Logger.set_output(function(msg) io.stderr:write(msg .. "\n") end)
  end)

  it("is disabled by default", function()
    Logger.disable()
    Logger.error("should not appear")
    assert.are.equal(0, #captured)
  end)

  it("logs messages at the configured level", function()
    Logger.set_level("ERROR")
    Logger.error("an error: %s", "test")
    assert.are.equal(1, #captured)
    assert.truthy(captured[1]:match("%[ERROR%]"))
    assert.truthy(captured[1]:match("an error: test"))
  end)

  it("filters messages below the configured level", function()
    Logger.set_level("WARN")
    Logger.info("this is info")
    Logger.debug("this is debug")
    Logger.warn("this is warn")
    Logger.error("this is error")
    assert.are.equal(2, #captured) -- only warn and error
  end)

  it("accepts string level names case-insensitively", function()
    Logger.set_level("debug")
    Logger.debug("debug msg")
    assert.are.equal(1, #captured)
  end)

  describe("is_enabled", function()
    it("returns true for levels at or above current", function()
      Logger.set_level("WARN")
      assert.is_true(Logger.is_enabled("ERROR"))
      assert.is_true(Logger.is_enabled("WARN"))
      assert.is_false(Logger.is_enabled("INFO"))
    end)

    it("returns false when logging is disabled", function()
      Logger.disable()
      assert.is_false(Logger.is_enabled("ERROR"))
    end)
  end)

  describe("redact", function()
    it("returns [REDACTED] when redaction is enabled", function()
      Logger.set_redact_payloads(true)
      assert.are.equal("[REDACTED]", Logger.redact("secret"))
    end)

    it("returns the value when redaction is disabled", function()
      Logger.set_redact_payloads(false)
      assert.are.equal("secret", Logger.redact("secret"))
    end)
  end)
end)
