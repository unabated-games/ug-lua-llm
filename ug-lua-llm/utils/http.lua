local json = require "ug-lua-llm.utils.json"
local socket = require "socket"
local http_request = require "http.request"
local Error = require "ug-lua-llm.core.error"
local Lifecycle = require "ug-lua-llm.utils.lifecycle"

local HttpClient = {}

-- Status codes that are safe to retry
local RETRYABLE_STATUS = {
  [408] = true,  -- Request Timeout
  [409] = true,  -- Conflict (commonly retryable for idempotent requests)
  [425] = true,  -- Too Early
  [429] = true,  -- Too Many Requests
  [500] = true,  -- Internal Server Error
  [502] = true,  -- Bad Gateway
  [503] = true,  -- Service Unavailable
  [504] = true,  -- Gateway Timeout
}

-- Create a new HTTP client
function HttpClient.new(config)
  local client = {
    config = config or {},
  }

  -- Set default headers
  client.headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  -- Add user-provided headers
  if config and config.headers then
    for k, v in pairs(config.headers) do
      client.headers[k] = v
    end
  end

  -- Set the metatable to find methods in HttpClient
  setmetatable(client, { __index = HttpClient })

  return client
end

-- Execute a single HTTP request (no retries)
function HttpClient:_do_request(method, url, payload, headers)
  -- Combine default headers with request-specific headers
  local merged_headers = {}
  for k, v in pairs(self.headers) do
    merged_headers[k] = v
  end
  for k, v in pairs(headers or {}) do
    merged_headers[k] = v
  end

  local ok, req_or_err = pcall(http_request.new_from_uri, url)
  if not ok or not req_or_err then
    local message = "Invalid HTTP URL: " .. tostring(req_or_err)
    return nil, message, Error.validation(
      self.config.provider_name, message, "invalid_url")
  end

  local req = req_or_err
  req.headers:upsert(":method", method)
  for name, value in pairs(merged_headers) do
    req.headers:upsert(name:lower(), tostring(value))
  end

  if payload ~= nil then
    local encoded_ok, request_body = pcall(json.encode, payload)
    if not encoded_ok then
      local message = "Failed to encode request JSON: " .. tostring(request_body)
      return nil, message, Error.serialization(
        self.config.provider_name, message, request_body)
    end
    req:set_body(request_body)
    -- lua-http appends "expect: 100-continue" for any body over 1024 bytes.
    -- Several LLM endpoints never send the interim 100 response, so the client
    -- stalls waiting for it, and a final response arriving instead makes
    -- lua-http drop the body entirely. Requests above that size then hang while
    -- smaller ones succeed. Send the body directly instead.
    req.headers:delete("expect")
  end

  local timeout = tonumber(self.config.timeout) or 60
  local deadline = Lifecycle.now() + timeout

  local go_ok, resp_headers, stream = pcall(req.go, req, timeout)
  if not go_ok or not resp_headers then
    local cause = resp_headers or stream
    local message = "HTTP request failed: " .. tostring(cause)
    return nil, message, Error.transport(
      self.config.provider_name, message, cause)
  end

  -- The configured timeout has to cover the whole exchange. Without a deadline
  -- here a server that sends headers and then stops writing would block
  -- forever, and a nil return would otherwise be mistaken for an empty body.
  local remaining = math.max(deadline - Lifecycle.now(), 0)
  local body_ok, body, body_err = pcall(stream.get_body_as_string, stream, remaining)
  if not body_ok then
    local message = "Failed to read HTTP response: " .. tostring(body)
    return nil, message, Error.transport(
      self.config.provider_name, message, body)
  end
  if body == nil then
    local message = "Failed to read HTTP response body: " .. tostring(body_err)
    local details = Error.transport(
      self.config.provider_name, message, body_err)
    details.retryable = true
    return nil, message, details
  end

  local code = tonumber(resp_headers:get(":status"))
  local headers_table = {}
  for name, value in resp_headers:each() do
    if name:sub(1, 1) ~= ":" then
      headers_table[name:lower()] = value
    end
  end

  -- Try to parse JSON response
  local parsed_body
  if body and body:len() > 0 then
    local success, result = pcall(function() return json.decode(body) end)
    if success then
      parsed_body = result
    else
      if code and code >= 200 and code < 300 then
        local message = "Failed to decode HTTP response JSON"
        local details = Error.new("decoding", message, {
          provider = self.config.provider_name,
          status = code,
          cause = tostring(result),
        })
        return nil, message, details
      end
      parsed_body = body
    end
  end

  return {
    status = code,
    headers = headers_table,
    body = parsed_body,
    raw_body = body
  }, nil
end

-- Compute backoff delay with jitter: min(base * 2^attempt, 60) + random jitter
local function backoff_delay(base, attempt)
  local delay = math.min(base * (2 ^ attempt), 60)
  -- Add jitter: 0% to 25% of delay
  local jitter = delay * 0.25 * math.random()
  return delay + jitter
end

local function rate_limit_delay(response)
  local headers = response and response.headers or {}
  local value = headers["retry-after"] or headers["x-ratelimit-reset-after"] or
    headers["x-ratelimit-reset-requests"]
  local delay = tonumber(value)
  if not delay and type(value) == "string" then
    local amount, unit = value:match("^(%d+%.?%d*)(%a+)$")
    if amount and (unit == "ms" or unit == "s" or unit == "m") then
      local scale = unit == "ms" and 0.001 or (unit == "m" and 60 or 1)
      delay = tonumber(amount) * scale
    end
  end
  if delay then return math.max(0, math.min(delay, 60)) end
  local reset = tonumber(headers["x-ratelimit-reset"])
  if reset then return math.max(0, math.min(reset - os.time(), 60)) end
end

local function default_should_retry(response, details)
  return (response and RETRYABLE_STATUS[response.status]) or
    (not response and details and details.retryable == true)
end

-- Make HTTP request with retry on transient errors
function HttpClient:request(method, url, payload, headers)
  local max_retries = math.max(0, tonumber(self.config.retries) or 3)
  local base_delay = math.max(0, tonumber(self.config.retry_delay) or 1)

  local context = {
    request_id = Lifecycle.request_id(self.config.provider_name),
    provider = tostring(self.config.provider_name or "unknown"):lower(),
    method = method,
    url = url,
    model = type(payload) == "table" and payload.model or nil,
  }
  local response, err, details

  for attempt = 1, max_retries + 1 do
    context.attempt = attempt
    if Lifecycle.cancelled(self.config) then
      local message, cancelled = Lifecycle.cancel_error(
        context.provider, context.request_id, attempt - 1)
      Lifecycle.emit(self.config, "on_error",
        Lifecycle.metadata(context, { error = cancelled }))
      return nil, message, cancelled
    end

    Lifecycle.emit(self.config, "on_request", Lifecycle.metadata(context))
    local started = Lifecycle.now()
    response, err, details = self:_do_request(method, url, payload, headers)
    local elapsed = Lifecycle.now() - started
    if response then
      response.request_id, response.attempts = context.request_id, attempt
      Lifecycle.emit(self.config, "on_response", Lifecycle.metadata(context, {
        status = response.status,
        elapsed = elapsed,
        headers = Error.http(context.provider, response, "HTTP response").headers,
      }))
    end

    local attempt_error = details
    if not attempt_error and response and response.status >= 400 then
      attempt_error = Error.http(context.provider, response, "HTTP request failed")
    end

    local retry = default_should_retry(response, details)
    if type(self.config.retry_predicate) == "function" then
      local ok, decision = pcall(self.config.retry_predicate,
        Lifecycle.metadata(context, {
          status = response and response.status,
          error = attempt_error,
        }))
      retry = ok and decision == true
    end

    if not retry or attempt > max_retries then
      if details then
        details.attempts, details.request_id = attempt, context.request_id
      end
      if err or (response and response.status >= 400) then
        local final_error = details or Error.http(
          context.provider, response, err or "HTTP request failed")
        Lifecycle.emit(self.config, "on_error", Lifecycle.metadata(context, {
          status = response and response.status,
          elapsed = elapsed,
          error = final_error,
        }))
      end
      return response, err, details
    end

    local delay = rate_limit_delay(response) or backoff_delay(base_delay, attempt - 1)
    if type(self.config.backoff) == "function" then
      local ok, custom = pcall(self.config.backoff, Lifecycle.metadata(context, {
        status = response and response.status,
        error = attempt_error,
        suggested_delay = delay,
      }))
      if ok and tonumber(custom) then delay = math.max(0, tonumber(custom)) end
    end
    Lifecycle.emit(self.config, "on_retry", Lifecycle.metadata(context, {
      status = response and response.status,
      error = attempt_error,
      delay = delay,
      next_attempt = attempt + 1,
    }))
    if Lifecycle.cancelled(self.config) then
      local message, cancelled = Lifecycle.cancel_error(
        context.provider, context.request_id, attempt)
      Lifecycle.emit(self.config, "on_error",
        Lifecycle.metadata(context, { error = cancelled }))
      return nil, message, cancelled
    end
    socket.sleep(delay)
  end
end

-- Stream HTTP request with callback for each chunk
-- This is a basic implementation using socket.http directly
function HttpClient:stream_request(method, url, payload, callback, headers, control)
  if not callback or type(callback) ~= "function" then
    local message = "Callback is required for streaming"
    return nil, message, Error.validation(
      self.config.provider_name, message, "callback_required")
  end

  -- Combine default headers with request-specific headers.
  local merged_headers = {}
  for k, v in pairs(self.headers) do
    merged_headers[k] = v
  end
  for k, v in pairs(headers or {}) do
    merged_headers[k] = v
  end

  local HttpStreaming = require "ug-lua-llm.utils.http_streaming"
  control = control or self.config
  return HttpStreaming.stream_sse(
    url, merged_headers, payload, callback, control.timeout or
      self.config.timeout or 60, method, self.config.provider_name, control)
end

-- GET request helper
function HttpClient:get(url, headers)
  return self:request("GET", url, nil, headers)
end

-- POST request helper
function HttpClient:post(url, payload, headers)
  return self:request("POST", url, payload, headers)
end

-- PUT request helper
function HttpClient:put(url, payload, headers)
  return self:request("PUT", url, payload, headers)
end

-- DELETE request helper
function HttpClient:delete(url, headers)
  return self:request("DELETE", url, nil, headers)
end

return HttpClient
