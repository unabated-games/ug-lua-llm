-- Mock HTTP client for testing providers without hitting real APIs.
--
-- Usage:
--   local mock = require("spec.helpers.mock_http")
--   mock.reset()
--   mock.register("POST", "https://api.openai.com/v1/chat/completions", {
--     status = 200,
--     body = { choices = { { message = { content = "Hello" } } } },
--   })
--
--   -- Then create a provider and call it; its HTTP client will be intercepted.

local json = require("ug-lua-llm.utils.json")

local MockHttp = {}

local _responses = {}    -- keyed by "METHOD url"
local _requests = {}     -- ordered list of captured requests
local _default_response = nil

function MockHttp.reset()
  _responses = {}
  _requests = {}
  _default_response = nil
end

function MockHttp.register(method, url_pattern, response)
  local key = method:upper() .. " " .. url_pattern
  _responses[key] = response
end

function MockHttp.set_default(response)
  _default_response = response
end

function MockHttp.requests()
  return _requests
end

function MockHttp.last_request()
  return _requests[#_requests]
end

function MockHttp.request_count()
  return #_requests
end

-- Find the matching registered response for a given method + url.
-- Supports exact matches and Lua pattern matches.
local function find_response(method, url)
  local exact_key = method:upper() .. " " .. url
  if _responses[exact_key] then
    return _responses[exact_key]
  end

  -- Try pattern matches
  for key, resp in pairs(_responses) do
    local key_method, key_pattern = key:match("^(%S+) (.+)$")
    if key_method == method:upper() then
      if url:match(key_pattern) then
        return resp
      end
    end
  end

  return _default_response
end

-- Create a mock HTTP client instance that mimics HttpClient's interface.
function MockHttp.client()
  local client = {
    headers = {
      ["Content-Type"] = "application/json",
      ["Accept"] = "application/json",
    },
    config = {},
  }

  function client:_do_request(method, url, payload, headers)
    -- Record the request
    table.insert(_requests, {
      method = method,
      url = url,
      payload = payload,
      headers = headers,
    })

    local resp = find_response(method, url)
    if not resp then
      return nil, "No mock response registered for " .. method .. " " .. url
    end

    -- If resp.error is set, simulate a network failure
    if resp.error then
      return nil, resp.error
    end

    return {
      status = resp.status or 200,
      headers = resp.headers or {},
      body = resp.body,
      raw_body = resp.raw_body or (resp.body and json.encode(resp.body) or ""),
    }, nil
  end

  function client:request(method, url, payload, headers)
    return self:_do_request(method, url, payload, headers)
  end

  function client:get(url, headers)
    return self:request("GET", url, nil, headers)
  end

  function client:post(url, payload, headers)
    return self:request("POST", url, payload, headers)
  end

  function client:put(url, payload, headers)
    return self:request("PUT", url, payload, headers)
  end

  function client:delete(url, headers)
    return self:request("DELETE", url, nil, headers)
  end

  function client:stream_request(method, url, payload, callback, headers)
    -- Record the request
    table.insert(_requests, {
      method = method,
      url = url,
      payload = payload,
      headers = headers,
      streaming = true,
    })

    local resp = find_response(method, url)
    if not resp then
      return nil, "No mock response registered for " .. method .. " " .. url
    end

    if resp.error then
      return nil, resp.error
    end

    -- If the response has stream_chunks, call the callback for each
    if resp.stream_chunks then
      for _, chunk in ipairs(resp.stream_chunks) do
        callback(chunk)
      end
    end

    return {
      status = resp.status or 200,
      headers = resp.headers or {},
    }, nil
  end

  return client
end

-- Inject a mock HTTP client into a provider instance.
-- Returns the mock client for further assertions.
function MockHttp.inject(provider)
  local client = MockHttp.client()
  provider.http = client
  return client
end

return MockHttp
