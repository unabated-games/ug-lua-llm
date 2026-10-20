local Doctor = require("ug-lua-llm.doctor")

describe("installation doctor", function()
  it("returns diagnostics without accessing an endpoint by default", function()
    local report = Doctor.run()
    assert.is_true(report.offline)
    assert.is_truthy(report.lua_version)
    assert.is_truthy(report.package_path)
    assert.is_true(#report.checks > 0)
    assert.is_nil(report.endpoint_error)
  end)

  it("supports Lua 5.1 through 5.5", function()
    for _, version in ipairs({ "5.1", "5.2", "5.3", "5.4", "5.5" }) do
      assert.is_true(Doctor.lua_supported(version), version)
    end
    for _, version in ipairs({ "5.0", "5.6", "unknown" }) do
      assert.is_false(Doctor.lua_supported(version), version)
    end
  end)

  it("accepts the Lua it is running on", function()
    local report = Doctor.run()
    for _, check in ipairs(report.checks) do
      if check.name == "lua-supported" then
        assert.are.equal("pass", check.status, check.message)
      end
    end
  end)

  it("prints statuses and remediation", function()
    local chunks = {}
    local output = { write = function(_, value) chunks[#chunks + 1] = value end }
    local ok = Doctor.print({ ok = false, checks = {{
      name = "test", status = "fail", message = "missing", fix = "install it",
    }} }, output)
    local rendered = table.concat(chunks)
    assert.is_false(ok)
    assert.matches("FAIL", rendered, 1, true)
    assert.matches("Fix: install it", rendered, 1, true)
  end)

  it("checks credential presence without returning its value", function()
    local report = Doctor.run({
      env_file = "spec/fixtures/doctor.env.fixture",
      provider = "claude",
    })
    local encoded = require("ug-lua-llm.utils.json").encode(report)
    assert.matches("ANTHROPIC_API_KEY is set", encoded, 1, true)
    assert.is_nil(encoded:find("doctor-secret-must-not-appear", 1, true))
  end)
end)
