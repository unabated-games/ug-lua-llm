local Provider = require 'ug-lua-llm.core.provider'
local Options = require 'ug-lua-llm.utils.options'
local Pagination = require 'ug-lua-llm.utils.pagination'
local Response = require 'ug-lua-llm.core.response'
local Structured = require 'ug-lua-llm.core.structured'

local GeminiProvider = {}
setmetatable(GeminiProvider, { __index = Provider })

function GeminiProvider.new(config)
  config = config or {}
  config.base_url = config.base_url or "https://generativelanguage.googleapis.com/v1beta"
  config.provider_name = "gemini"

  if not config.api_key then
    error("Gemini API key is required")
  end

  config.model = config.model or "gemini-3.6-flash"

  local provider = Provider.new(config)

  provider.http.headers["x-goog-api-key"] = config.api_key

  setmetatable(provider, { __index = GeminiProvider })
  return provider
end

-- Build the request URL. The API key travels as a header, not in the query
-- string, so it stays out of logs and proxy access records.
function GeminiProvider:_url(model, action)
  return string.format("%s/models/%s:%s", self.config.base_url, model, action)
end

-- Convert standard messages to Gemini format
function GeminiProvider:_format_contents(messages)
  local contents = {}
  -- Gemini takes a single system instruction, but a transcript may carry
  -- several system messages. Assigning discarded every one but the last,
  -- silently; join them the way the Claude provider joins its own.
  local system_parts = {}

  for _, msg in ipairs(messages) do
    if msg.role == "system" then
      if type(msg.content) == "string" and msg.content ~= "" then
        system_parts[#system_parts + 1] = msg.content
      end
    else
      local role = msg.role == "assistant" and "model" or "user"
      table.insert(contents, {
        role = role,
        parts = type(msg.content) == "table" and msg.content or { { text = msg.content } }
      })
    end
  end

  local system_instruction = nil
  if #system_parts > 0 then
    system_instruction = {
      parts = { { text = table.concat(system_parts, "\n\n") } },
    }
  end

  return contents, system_instruction
end

-- Gemini reports usage under its own names. Rebuilding the table from three of
-- them dropped the rest -- including thoughtsTokenCount, the explicit reasoning
-- count Response.normalize looks for -- so the cost of thinking had to be
-- re-derived from the gap between the total and its parts, and was simply
-- absent whenever the total did not include it. Carry every field through and
-- add the normalized names beside them.
local function normalize_usage(metadata)
  if type(metadata) ~= "table" then return nil end
  local usage = {}
  for key, value in pairs(metadata) do usage[key] = value end
  usage.prompt_tokens = metadata.promptTokenCount
  usage.completion_tokens = metadata.candidatesTokenCount
  usage.total_tokens = metadata.totalTokenCount
  return usage
end

-- Convert Gemini response to OpenAI-like format for consistency
function GeminiProvider:_format_response(body)
  if not body or not body.candidates or not body.candidates[1] then
    -- A blocked prompt answers 200 with promptFeedback and no candidates.
    -- Returning the raw body handed callers an unfamiliar shape with no text
    -- and no finish_reason; normalize it so the refusal is legible.
    local feedback = type(body) == "table" and body.promptFeedback
    if type(feedback) == "table" and feedback.blockReason then
      -- Normalized like any other reply, not returned raw: `text` is
      -- contractually a string, and returning this table directly left it nil
      -- for exactly the callers least likely to be checking.
      return Response.normalize("gemini", {
        content = "",
        finish_reason = "content_filter",
        blocked = true,
        block_reason = feedback.blockReason,
        safety_ratings = feedback.safetyRatings,
        model = type(body) == "table" and body.modelVersion or nil,
        raw = body,
      })
    end
    -- Neither candidates nor a block reason: an unfamiliar shape, but the
    -- caller's contract still holds. Returning the body directly left `text`
    -- nil and `provider` unset -- the last path in this function that did.
    return Response.normalize("gemini", {
      content = "",
      finish_reason = nil,
      model = type(body) == "table" and body.modelVersion or nil,
      raw = body,
    })
  end

  local candidate = body.candidates[1]
  local content = ""
  local tool_calls = {}

  if candidate.content and candidate.content.parts then
    for _, part in ipairs(candidate.content.parts) do
      if part.text then
        content = content .. part.text
      elseif part.functionCall then
        table.insert(tool_calls, {
          -- Gemini supplies its own call id on newer models. Synthesizing one
          -- unconditionally threw away the value the follow-up correlates on.
          id = part.functionCall.id or ("call_" .. #tool_calls + 1),
          type = "function",
          ["function"] = {
            name = part.functionCall.name,
            arguments = require('ug-lua-llm.utils.json').encode(part.functionCall.args or {})
          }
        })
      end
    end
  end

  local result = {
    content = content,
    tool_calls = #tool_calls > 0 and tool_calls or nil,
    -- The model's own parts, kept intact so a tool follow-up can echo them
    -- back. Gemini 3.x signs each functionCall with a thoughtSignature and
    -- rejects a turn that replays the call without it, so a part rebuilt from
    -- name and args cannot be sent back.
    parts = candidate.content and candidate.content.parts or nil,
    model = body.modelVersion,
    finish_reason = candidate.finishReason,
    usage = normalize_usage(body.usageMetadata),
    raw = body,
  }

  return Response.normalize("gemini", result)
end

function GeminiProvider:list_models(options)
  options = options or {}
  local models = {}
  local token
  local max_pages = options.all_pages == false and 1 or (options.max_pages or 100)
  for _ = 1, max_pages do
    local url = Pagination.query(self.config.base_url .. "/models", {
      pageSize = options.page_size,
      pageToken = token,
    })
    local response, err, details = self.http:get(url)
    if err or not response then
      return nil, self:transport_error(err, details, "Failed to fetch models")
    end
    if response.status ~= 200 then
      return nil, self:format_error(response, "Failed to fetch models")
    end
    for _, m in ipairs((response.body and response.body.models) or {}) do
      table.insert(models, {
        id = m.name and m.name:gsub("^models/", "") or "",
        name = m.displayName or m.name or "",
      })
    end
    local next_token = response.body and response.body.nextPageToken
    if not next_token or next_token == token then break end
    token = next_token
  end
  return models
end

-- Gemini's agentic primitive. `input` may be a string or typed multimodal
-- items. generateContent remains available through chat() for conventional
-- transcript-based calls.
function GeminiProvider:interaction(input, options)
  options = options or {}
  local payload = Options.payload({
    model = options.model or self.config.model,
    input = input,
  }, options)
  if options.system_instruction then payload.system_instruction = options.system_instruction end
  if options.tools then payload.tools = options.tools end
  if options.response_format then payload.response_format = options.response_format end

  local response, err, details = self.http:post(self.config.base_url .. "/interactions", payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Interaction request failed")
  end
  if response.status ~= 200 then
    return nil, self:format_error(response, "Interaction request failed")
  end

  local text_parts, tool_calls = {}, {}
  for _, step in ipairs((response.body and response.body.steps) or {}) do
    if step.type == "model_output" then
      for _, part in ipairs(step.content or {}) do
        if part.type == "text" and part.text then text_parts[#text_parts + 1] = part.text end
      end
    elseif step.type == "function_call" then
      tool_calls[#tool_calls + 1] = {
        id = step.id, type = "function",
        ["function"] = {
          name = step.name,
          arguments = require("ug-lua-llm.utils.json").encode(step.arguments or {}),
        },
      }
    end
  end
  return Response.normalize("gemini", {
    id = response.body.id,
    model = response.body.model,
    content = table.concat(text_parts),
    tool_calls = #tool_calls > 0 and tool_calls or nil,
    finish_reason = response.body.status,
    usage = response.body.usage,
    steps = response.body.steps,
    raw = response.body,
  })
end

function GeminiProvider:complete(prompt, options)
  local messages = {
    { role = "user", content = prompt }
  }
  return self:chat(messages, options)
end

function GeminiProvider:chat(messages, options)
  options = options or {}
  local model = options.model or self.config.model
  local url = self:_url(model, "generateContent")

  local contents, system_instruction = self:_format_contents(messages)

  local payload = Options.payload({
    contents = contents,
    generationConfig = {
      temperature = options.temperature or self.config.temperature,
      maxOutputTokens = options.max_tokens or self.config.max_tokens,
    }
  }, options)

  if system_instruction then
    payload.systemInstruction = system_instruction
  end

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat request failed")
  end

  return self:_format_response(response.body)
end

-- Gemini spells tool choice as a nested toolConfig rather than OpenAI's
-- `tool_choice`, so the OpenAI spelling is not merely rejected -- it is a field
-- Gemini has never heard of. Passing it through unchanged meant a caller asking
-- to force a tool, or to forbid one, silently got neither.
local FUNCTION_CALLING_MODE = {
  auto = "AUTO",
  required = "ANY",
  any = "ANY",
  none = "NONE",
}

local function tool_config(choice)
  if choice == nil then return nil end

  if type(choice) == "string" then
    local mode = FUNCTION_CALLING_MODE[choice:lower()]
    if not mode then return nil end
    return { functionCallingConfig = { mode = mode } }
  end

  if type(choice) == "table" then
    -- Naming a tool is a demand for that one: OpenAI's
    -- { type = "function", function = { name = ... } }, and Claude's
    -- { type = "tool", name = ... }, both mean the same thing here.
    local named = choice.name or (type(choice["function"]) == "table" and
      choice["function"].name)
    if named then
      return { functionCallingConfig = {
        mode = "ANY", allowedFunctionNames = { named } } }
    end
    local mode = type(choice.type) == "string" and
      FUNCTION_CALLING_MODE[choice.type:lower()]
    if mode then return { functionCallingConfig = { mode = mode } } end
  end

  return nil
end

function GeminiProvider:chat_with_tools(messages, tools, options)
  options = options or {}
  local model = options.model or self.config.model
  local url = self:_url(model, "generateContent")

  local contents, system_instruction = self:_format_contents(messages)

  -- Convert tools to Gemini format
  local gemini_tools = {}
  local function_declarations = {}
  for _, tool in ipairs(tools) do
    table.insert(function_declarations, {
      name = tool.name,
      description = tool.description,
      -- Same restricted subset as a response schema. Forwarded verbatim, a
      -- tool schema written for OpenAI strict mode -- where
      -- `additionalProperties: false` is required -- fails here with
      -- 'Unknown name "additionalProperties"'.
      parameters = Structured.gemini_schema(tool.parameters),
    })
  end
  table.insert(gemini_tools, { functionDeclarations = function_declarations })

  local payload = Options.payload({
    contents = contents,
    tools = gemini_tools,
    generationConfig = {
      temperature = options.temperature or self.config.temperature,
      maxOutputTokens = options.max_tokens or self.config.max_tokens,
    }
  }, options)

  if system_instruction then
    payload.systemInstruction = system_instruction
  end

  local config = tool_config(options.tool_choice)
  if config and payload.toolConfig == nil then payload.toolConfig = config end

  local response, err, details = self.http:post(url, payload)
  if err or not response then
    return nil, self:transport_error(err, details, "Chat with tools request failed")
  end

  if response.status ~= 200 then
    return nil, self:format_error(response, "Chat with tools request failed")
  end

  return self:_format_response(response.body)
end

-- Stream a chat response
function GeminiProvider:stream_complete(prompt, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  local messages = { { role = "user", content = prompt } }
  return self:stream_chat(messages, function(delta, full)
    if delta.content then
      callback({
        content = delta.content,
        text = delta.content,
        finish_reason = delta.finish_reason,
        choices = { { text = delta.content, index = 0, finish_reason = delta.finish_reason } },
        delta = true
      }, full)
    end
  end, options)
end

function GeminiProvider:stream_chat(messages, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  options = options or {}
  local model = options.model or self.config.model
  local url = self:_url(model, "streamGenerateContent") .. "?alt=sse"

  local contents, system_instruction = self:_format_contents(messages)

  local payload = Options.payload({
    contents = contents,
    generationConfig = {
      temperature = options.temperature or self.config.temperature,
      maxOutputTokens = options.max_tokens or self.config.max_tokens,
    }
  }, options)

  if system_instruction then
    payload.systemInstruction = system_instruction
  end

  local accumulated_content = ""
  local current_response = {
    content = "",
    model = model,
    finish_reason = nil,
  }

  -- Use the basic HTTP streaming from the http client
  local result, _err = self.http:stream_request("POST", url, payload, function(chunk)
    if chunk and chunk.candidates and chunk.candidates[1] then
      local candidate = chunk.candidates[1]
      local delta_content = ""

      if candidate.content and candidate.content.parts then
        for _, part in ipairs(candidate.content.parts) do
          if part.text then
            delta_content = delta_content .. part.text
          end
        end
      end

      accumulated_content = accumulated_content .. delta_content
      current_response.content = accumulated_content

      if candidate.finishReason then
        current_response.finish_reason = candidate.finishReason
      end

      callback({
        content = delta_content,
        finish_reason = candidate.finishReason,
        delta = true
      }, current_response)
    end
  end, nil, options)

  if not result then
    -- Fall back to non-streaming
    -- A caller who asked not to fall back wants the streaming failure, not a
    -- whole reply that hides it. Only the compatible family honoured this, so
    -- the bundled conformance runner -- whose whole job is detecting broken
    -- SSE -- reported streaming OK on the other three: the fallback's single
    -- callback counts as a chunk.
    if options and options.stream_fallback == false then
      return nil, self:transport_error(_err, nil, "Streaming request failed")
    end
    local response, chat_err, details = self:chat(messages, options)
    if chat_err or not response then
      return nil, chat_err, details
    end

    callback({
      content = response.content,
      finish_reason = response.finish_reason,
      delta = true
    }, response)

    return response
  end

  -- The fallback above returns a normalized response; this, the successful
  -- path, returned the raw accumulator -- no text, no provider, no
  -- finish_reason normalization.
  return Response.normalize("gemini", current_response)
end

function GeminiProvider:stream_chat_with_tools(messages, tools, callback, options)
  if not callback or type(callback) ~= "function" then
    return nil, self:validation_error(
      "Callback function is required for streaming", "callback_required")
  end

  -- Gemini streaming with tools: fall back to non-streaming since tool calls
  -- arrive as complete function calls in the response, not streamed incrementally
  local response, err, details = self:chat_with_tools(messages, tools, options)
  if err or not response then
    return nil, err, details
  end

  if response.tool_calls then
    callback({
      tool_calls = response.tool_calls,
      finish_reason = response.finish_reason,
      delta = true
    }, response)
  else
    callback({
      content = response.content,
      finish_reason = response.finish_reason,
      delta = true
    }, response)
  end

  return response
end

return GeminiProvider
