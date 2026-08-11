-- Accumulate OpenAI Chat Completions SSE chunks into one compatibility
-- response while emitting provider-neutral text and tool-call delta fields.
local JSON = require "ug-lua-llm.utils.json"

local ChatStream = {}

local function append_tool_call(state, delta)
  local index = delta.index or 0
  local call = state[index]
  if not call then
    call = {
      id = delta.id or "",
      type = delta.type or "function",
      ["function"] = { name = "", arguments = "" },
    }
    state[index] = call
  elseif delta.id then
    call.id = delta.id
  end

  local fn = delta["function"]
  if fn then
    call["function"].name = call["function"].name .. (fn.name or "")
    call["function"].arguments = call["function"].arguments ..
      (fn.arguments or "")
  end
  return call
end

function ChatStream.new(model, provider, include_tools)
  local accumulator = {
    model = model,
    provider = provider or "openai-compatible",
    include_tools = include_tools == true,
    text_by_choice = {},
    tools_by_choice = {},
    current = {
      choices = {},
      id = nil,
      model = model,
      object = "chat.completion",
      provider = provider or "openai-compatible",
      text = "",
      content = "",
      raw_events = {},
    },
  }
  return setmetatable(accumulator, { __index = ChatStream })
end

function ChatStream:consume(chunk, callback)
  if type(chunk) ~= "table" or type(chunk.choices) ~= "table" then return end
  self.current.raw_events[#self.current.raw_events + 1] = chunk
  self.current.id = chunk.id or self.current.id
  self.current.model = chunk.model or self.current.model
  self.current.object = chunk.object or self.current.object

  for position, choice in ipairs(chunk.choices) do
    local choice_index = choice.index
    if choice_index == nil then choice_index = position - 1 end
    local slot = choice_index + 1
    local current_choice = self.current.choices[slot]
    if not current_choice then
      current_choice = {
        message = { role = "assistant", content = "" },
        index = choice_index,
        finish_reason = nil,
      }
      if self.include_tools then current_choice.message.tool_calls = {} end
      self.current.choices[slot] = current_choice
      self.text_by_choice[slot] = ""
      self.tools_by_choice[slot] = {}
    end

    local raw_delta = choice.delta or {}
    -- The opening chunk of an OpenAI-compatible stream is normally
    -- {"role":"assistant","content":null}. A bare tostring() would append the
    -- backend's null sentinel to the accumulated text.
    local text = JSON.string_value(raw_delta.content) or ""
    if text ~= "" then
      self.text_by_choice[slot] = self.text_by_choice[slot] .. text
      current_choice.message.content = self.text_by_choice[slot]
    end

    local delta_tools = nil
    if self.include_tools and raw_delta.tool_calls then
      delta_tools = raw_delta.tool_calls
      for _, tool_delta in ipairs(delta_tools) do
        local call = append_tool_call(self.tools_by_choice[slot], tool_delta)
        local call_slot = (tool_delta.index or 0) + 1
        current_choice.message.tool_calls[call_slot] = call
      end
    end

    if choice.finish_reason then current_choice.finish_reason = choice.finish_reason end
    if choice_index == 0 then
      self.current.text = current_choice.message.content
      self.current.content = current_choice.message.content
      self.current.tool_calls = current_choice.message.tool_calls
      self.current.finish_reason = current_choice.finish_reason
    end

    callback({
      choices = {{
        index = choice_index,
        delta = raw_delta,
        finish_reason = choice.finish_reason,
      }},
      content = text,
      text = text,
      tool_calls = delta_tools,
      finish_reason = choice.finish_reason,
      provider = self.provider,
      raw = chunk,
      delta = true,
    }, self.current)
  end
end

function ChatStream.fallback_delta(response, provider)
  local choice = response and response.choices and response.choices[1]
  local message = choice and JSON.value(choice.message) or {}
  local tool_calls = JSON.value(message.tool_calls)
  local has_tools = type(tool_calls) == "table" and next(tool_calls) ~= nil
  local text = JSON.string_value(message.content) or
    (response and JSON.string_value(response.text)) or ""
  return {
    choices = {{
      index = 0,
      delta = has_tools and { tool_calls = tool_calls } or { content = text },
      finish_reason = has_tools and "tool_calls" or
        choice and choice.finish_reason or "stop",
    }},
    content = text,
    text = text,
    tool_calls = has_tools and tool_calls or nil,
    finish_reason = has_tools and "tool_calls" or
      choice and choice.finish_reason or "stop",
    provider = provider,
    delta = true,
  }
end

return ChatStream
