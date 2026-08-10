local Conformance = {}

local function record(report, name, value, err, details)
  local ok = value ~= nil
  report.checks[#report.checks + 1] = {
    name = name,
    ok = ok,
    error = err,
    details = details,
  }
  if not ok then report.ok = false end
  return ok
end

function Conformance.run(config)
  config = config or {}
  local UGLuaLLM = require "ug-lua-llm"
  local client = config.client or UGLuaLLM.openai_compatible(config)
  local report = { ok = true, checks = {} }

  local capabilities = client:capabilities()
  report.capabilities = capabilities
  if capabilities.models then
    local models, err, details = client:list_models({ max_pages = 2 })
    record(report, "models", models, err, details)
  end

  local messages = {{ role = "user", content = config.prompt or "Reply with: ok" }}
  local response, err, details = client:chat(messages, {
    max_tokens = config.max_tokens or 16,
    temperature = 0,
  })
  record(report, "chat", response, err, details)

  if capabilities.streaming then
    local chunks = 0
    local streamed, stream_err, stream_details = client:stream_chat(
      messages, function(delta)
        if delta and (delta.content or delta.text) then chunks = chunks + 1 end
      end, { max_tokens = config.max_tokens or 16, temperature = 0,
        stream_fallback = false })
    local ok = record(report, "streaming", streamed, stream_err, stream_details)
    report.checks[#report.checks].chunks = chunks
    if ok and chunks == 0 then
      report.checks[#report.checks].ok = false
      report.checks[#report.checks].error = "stream completed without content chunks"
      report.ok = false
    end
  end

  return report
end

return Conformance
