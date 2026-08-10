local socket = require "socket"
local Error = require "ug-lua-llm.core.error"

local Lifecycle = {}
local sequence = 0

local function safe_url(url)
  return tostring(url or ""):gsub("%?.*$", "")
end

function Lifecycle.request_id(provider)
  sequence = sequence + 1
  return string.format("%s-%d-%d", tostring(provider or "llm"):lower(),
    os.time(), sequence)
end

function Lifecycle.now()
  return socket.gettime()
end

function Lifecycle.cancelled(config)
  local token = config and config.cancel_token
  if type(token) == "function" then
    local ok, result = pcall(token)
    return ok and result == true
  end
  return type(token) == "table" and token.cancelled == true
end

function Lifecycle.cancel_error(provider, request_id, attempt)
  local message = "Request cancelled"
  return message, Error.new("cancelled", message, {
    provider = type(provider) == "string" and provider:lower() or provider,
    request_id = request_id,
    attempts = attempt or 0,
  })
end

function Lifecycle.metadata(context, fields)
  local meta = {
    request_id = context.request_id,
    provider = context.provider,
    method = context.method,
    url = safe_url(context.url),
    model = context.model,
    attempt = context.attempt,
  }
  for key, value in pairs(fields or {}) do meta[key] = value end
  return Error.sanitize(meta)
end

function Lifecycle.emit(config, name, meta)
  local hook = config and config[name]
  if type(hook) ~= "function" then return end
  -- Instrumentation must never turn a successful model request into a failure.
  pcall(hook, meta)
end

return Lifecycle
