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
