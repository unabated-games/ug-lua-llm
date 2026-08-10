local Error = {}

local RETRYABLE_STATUS = {
  [408] = true, [409] = true, [425] = true, [429] = true,
  [500] = true, [502] = true, [503] = true, [504] = true,
}

local SAFE_HEADERS = {
  ["retry-after"] = true,
  ["request-id"] = true,
  ["x-request-id"] = true,
  ["anthropic-request-id"] = true,
  ["cf-ray"] = true,
  ["x-ratelimit-limit-requests"] = true,
  ["x-ratelimit-remaining-requests"] = true,
  ["x-ratelimit-reset-requests"] = true,
  ["x-ratelimit-reset"] = true,
  ["x-ratelimit-reset-after"] = true,
}

local function sensitive(key)
  key = tostring(key):lower()
  return key:find("key", 1, true) or key:find("token", 1, true) or
    key:find("secret", 1, true) or key:find("password", 1, true) or
    key:find("authorization", 1, true) or key:find("credential", 1, true)
end

local function sanitize(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return "[circular]" end
  seen[value] = true
  local result = {}
  for key, item in pairs(value) do
    result[key] = sensitive(key) and "[REDACTED]" or sanitize(item, seen)
  end
  seen[value] = nil
  return result
end

local function safe_headers(headers)
  local result = {}
  for name, value in pairs(headers or {}) do
    local lower = tostring(name):lower()
    if SAFE_HEADERS[lower] then result[lower] = value end
  end
  return result
end

local function normalize_provider(provider)
  if type(provider) == "string" then return provider:lower() end
  return provider
end

function Error.new(kind, message, fields)
  local details = {
    kind = kind,
    message = tostring(message or "Unknown error"),
    retryable = false,
  }
  for key, value in pairs(fields or {}) do details[key] = value end
  return details
end

function Error.validation(provider, message, code)
  return Error.new("validation", message, {
    provider = normalize_provider(provider),
    code = code,
  })
end

function Error.transport(provider, message, cause)
  local text = tostring(cause or message or "Transport error")
  local is_timeout = text:lower():find("timeout", 1, true) ~= nil or
    text:lower():find("timed out", 1, true) ~= nil
  return Error.new(is_timeout and "timeout" or "transport", message, {
    provider = normalize_provider(provider),
    cause = text,
    retryable = true,
  })
end

function Error.serialization(provider, message, cause)
  return Error.new("serialization", message, {
    provider = normalize_provider(provider),
    cause = tostring(cause or message),
  })
end

function Error.http(provider, response, message)
  response = response or {}
  local status = tonumber(response.status)
  local body = sanitize(response.body)
  local code
  if type(body) == "table" and type(body.error) == "table" then
    code = body.error.code or body.error.type
  end
  return Error.new("http", message, {
    provider = normalize_provider(provider),
    status = status,
    code = code,
    retryable = RETRYABLE_STATUS[status] == true,
    headers = safe_headers(response.headers),
    body = body,
    request_id = response.request_id,
    attempts = response.attempts,
  })
end

function Error.sanitize(value)
  return sanitize(value)
end

return Error
