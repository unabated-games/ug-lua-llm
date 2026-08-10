-- Modern streaming client
local json = require("ug-lua-llm.utils.json")
local http_request = require("http.request")
local Error = require("ug-lua-llm.core.error")
local Lifecycle = require("ug-lua-llm.utils.lifecycle")

local HttpStreaming = {}

function HttpStreaming.new_sse_parser(event_callback)
  local parser = { buffer = "", data_lines = {}, done = false }

  function parser:dispatch()
    if #self.data_lines == 0 then return end
    local data = table.concat(self.data_lines, "\n")
    self.data_lines = {}
    if data == "[DONE]" then self.done = true return end
    local decoded_ok, decoded = pcall(json.decode, data)
    event_callback(decoded_ok and decoded or data)
  end

  function parser:feed(chunk)
    self.buffer = self.buffer .. (chunk or "")
    while not self.done do
      local line_end = self.buffer:find("\n", 1, true)
      if not line_end then break end
      local line = self.buffer:sub(1, line_end - 1):gsub("\r$", "")
      self.buffer = self.buffer:sub(line_end + 1)
      if line == "" then
        self:dispatch()
      elseif line:sub(1, 1) ~= ":" then
        local field, value = line:match("^([^:]+):%s?(.*)$")
        if field == "data" then self.data_lines[#self.data_lines + 1] = value end
      end
    end
  end

  function parser:finish()
    if self.buffer ~= "" then
      local line = self.buffer:gsub("\r$", "")
      local field, value = line:match("^([^:]+):%s?(.*)$")
      if field == "data" then self.data_lines[#self.data_lines + 1] = value end
      self.buffer = ""
    end
    self:dispatch()
  end

  return parser
end

local function make_request(url, headers_table, payload, timeout, method, provider)
  local ok, req_or_err = pcall(http_request.new_from_uri, url)
  if not ok or not req_or_err then
    local message = "Invalid HTTP URL: " .. tostring(req_or_err)
    return nil, nil, message,
      Error.validation(provider, message, "invalid_url")
  end

  local req = req_or_err
  req.headers:upsert(":method", method or "POST")
  for name, value in pairs(headers_table or {}) do
    req.headers:upsert(name:lower(), tostring(value))
  end
  req.headers:upsert("content-type", "application/json")
  req.headers:upsert("accept", "text/event-stream")

  if payload ~= nil then
    local encoded_ok, body = pcall(json.encode, payload)
    if not encoded_ok then
      local message = "Failed to encode request JSON: " .. tostring(body)
      return nil, nil, message, Error.serialization(provider, message, body)
    end
    req:set_body(body)
  end

  local go_ok, response_headers, stream = pcall(req.go, req, timeout or 60)
  if not go_ok or not response_headers then
    local cause = response_headers or stream
    local message = "HTTP connection failed: " .. tostring(cause)
    return nil, nil, message, Error.transport(provider, message, cause)
  end
  return response_headers, stream
end

-- Provider-neutral SSE reader. It handles CRLF, arbitrary network chunking,
-- comments, and multiline data fields. TLS and hostname verification are
-- delegated to lua-http/luaossl rather than a hand-built raw socket.
function HttpStreaming.stream_sse(url, headers_table, payload, event_callback,
                                  timeout, method, provider, control)
  control = control or {}
  local context = {
    request_id = Lifecycle.request_id(provider),
    provider = tostring(provider or "unknown"):lower(),
    method = method or "POST",
    url = url,
    model = type(payload) == "table" and payload.model or nil,
    attempt = 1,
  }
  if Lifecycle.cancelled(control) then
    local message, cancelled = Lifecycle.cancel_error(
      context.provider, context.request_id, 0)
    Lifecycle.emit(control, "on_error",
      Lifecycle.metadata(context, { error = cancelled }))
    return nil, message, cancelled
  end
  Lifecycle.emit(control, "on_request", Lifecycle.metadata(context))
  local started = Lifecycle.now()
  local headers, stream, err, details = make_request(
    url, headers_table, payload, timeout, method, provider)
  if not headers then
    details.request_id, details.attempts = context.request_id, 1
    Lifecycle.emit(control, "on_error", Lifecycle.metadata(context, {
      elapsed = Lifecycle.now() - started, error = details,
    }))
    return nil, err, details
  end

  local status = tonumber(headers:get(":status"))
  if not status or status < 200 or status >= 300 then
    local body_ok, body = pcall(stream.get_body_as_string, stream)
    if not body_ok then body = tostring(body) end
    local message = "HTTP error: " .. tostring(status) .. " - " .. tostring(body)
    local decoded_ok, decoded = pcall(json.decode, body or "")
    local response = {
      status = status,
      headers = {},
      body = decoded_ok and decoded or body,
    }
    for name, value in headers:each() do
      if name:sub(1, 1) ~= ":" then response.headers[name:lower()] = value end
    end
    response.request_id, response.attempts = context.request_id, 1
    local http_error = Error.http(provider, response, message)
    Lifecycle.emit(control, "on_response", Lifecycle.metadata(context, {
      status = status, elapsed = Lifecycle.now() - started,
      headers = http_error.headers,
    }))
    Lifecycle.emit(control, "on_error", Lifecycle.metadata(context, {
      status = status, elapsed = Lifecycle.now() - started, error = http_error,
    }))
    return nil, message, http_error
  end

  local parser = HttpStreaming.new_sse_parser(event_callback)
  local read_ok, read_err = pcall(function()
    for chunk in stream:each_chunk() do
      if Lifecycle.cancelled(control) then error("__ug_lua_llm_cancelled__") end
      parser:feed(chunk)
      if parser.done then break end
    end
  end)
  if not read_ok then
    if tostring(read_err):find("__ug_lua_llm_cancelled__", 1, true) then
      local message, cancelled = Lifecycle.cancel_error(
        context.provider, context.request_id, 1)
      Lifecycle.emit(control, "on_error", Lifecycle.metadata(context, {
        elapsed = Lifecycle.now() - started, error = cancelled,
      }))
      return nil, message, cancelled
    end
    local message = "Failed to read streaming response: " .. tostring(read_err)
    local transport = Error.transport(provider, message, read_err)
    transport.request_id, transport.attempts = context.request_id, 1
    Lifecycle.emit(control, "on_error", Lifecycle.metadata(context, {
      elapsed = Lifecycle.now() - started, error = transport,
    }))
    return nil, message, transport
  end
  parser:finish()
  Lifecycle.emit(control, "on_response", Lifecycle.metadata(context, {
    status = status, elapsed = Lifecycle.now() - started,
  }))
  return { status = status, headers = headers,
    request_id = context.request_id, attempts = 1 }, nil
end

-- Stream from Claude API with real-time event handling
function HttpStreaming.stream_claude(url, headers_table, payload, event_callback,
                                     provider, control)
  do
    local result, err, details = HttpStreaming.stream_sse(
      url, headers_table, payload, event_callback,
      (control and control.timeout) or 60, "POST", provider, control)
    if not result then return nil, err, details end
    return true
  end
end

-- Stream from OpenAI API with real-time event handling
function HttpStreaming.stream_openai(url, headers_table, payload, event_callback,
                                     provider, control)
  local function normalize_event(event)
    if type(event) == "table" and event.choices then
      for _, choice in ipairs(event.choices) do
        if type(choice.delta) == "string" then
          choice.delta = { content = choice.delta }
        elseif choice.delta and choice.delta.content == json.null then
          choice.delta.content = nil
        end
      end
    end
    event_callback(event)
  end

  local result, err, details = HttpStreaming.stream_sse(
    url, headers_table, payload, normalize_event,
    (control and control.timeout) or 60, "POST", provider, control)
  if not result then return nil, err, details end
  return true
end

return HttpStreaming
