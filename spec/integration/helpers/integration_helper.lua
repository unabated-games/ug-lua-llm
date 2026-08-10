local UGLuaLLM = require("ug-lua-llm")
local Embeddings = require("ug-lua-llm.core.embeddings")
local env = require("ug-lua-llm.utils.env")

-- Load .env file from project root (silently ignored if missing)
env.load(".env")

local H = {}

--- Check if an environment variable is set and non-empty.
function H.has_env(var)
  local val = env.get(var)
  return val and val ~= ""
end

--- Return the value of an environment variable (checks .env then system).
function H.get_env(var)
  return env.get(var)
end

--- Standard tool definition reused across all providers.
H.get_weather_tool = {
  name = "get_weather",
  description = "Get the current weather for a given location",
  parameters = {
    type = "object",
    properties = {
      location = { type = "string", description = "City name, e.g. Paris" },
    },
    required = { "location" },
  },
}

-- Client factories --------------------------------------------------------

function H.openai_client(overrides)
  local config = {
    api_key = env.get("OPENAI_API_KEY"),
    model = "gpt-5.6-luna",
    max_tokens = 64,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new("openai", config)
end

function H.claude_client(overrides)
  local config = {
    api_key = env.get("ANTHROPIC_API_KEY"),
    model = "claude-haiku-4-5-20251001",
    max_tokens = 64,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new("claude", config)
end

function H.gemini_client(overrides)
  local config = {
    api_key = env.get("GEMINI_API_KEY"),
    model = "gemini-2.5-flash-lite",
    max_tokens = 64,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new("gemini", config)
end

function H.openai_embeddings()
  return Embeddings.new("openai", {
    api_key = env.get("OPENAI_API_KEY"),
    base_url = "https://api.openai.com/v1",
    timeout = 30,
    retries = 0,
  })
end

function H.gemini_embeddings()
  return Embeddings.new("gemini", {
    api_key = env.get("GEMINI_API_KEY"),
    embedding_model = "gemini-embedding-001",
    timeout = 30,
    retries = 0,
  })
end

-- Assertion helpers -------------------------------------------------------
-- Use plain Lua error() so these work from require'd modules (busted's
-- assert global is not available outside spec files).

function H.assert_nonempty_string(value, label)
  label = label or "value"
  if type(value) ~= "string" then
    error(label .. " should be a string, got " .. type(value), 2)
  end
  if #value == 0 then
    error(label .. " should be non-empty", 2)
  end
end

function H.assert_valid_embeddings(result)
  if not result then
    error("embeddings result should not be nil", 2)
  end
  if not result.embeddings then
    error("result should contain embeddings", 2)
  end
  if #result.embeddings == 0 then
    error("should have at least one embedding", 2)
  end

  local emb = result.embeddings[1].embedding
  if not emb then
    error("embedding vector should not be nil", 2)
  end
  if #emb == 0 then
    error("embedding vector should be non-empty", 2)
  end
  if type(emb[1]) ~= "number" then
    error("embedding values should be numbers, got " .. type(emb[1]), 2)
  end
end

return H
