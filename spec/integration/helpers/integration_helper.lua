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
    -- Track the documented default. Google retires older models for new
    -- users, which turns a pinned one into a 404 that looks like a defect.
    model = "gemini-3.6-flash",
    -- Reasoning happens inside the output allowance. At 64 the model
    -- intermittently spends the whole budget thinking and returns no text at
    -- all, which makes the assertions flaky rather than wrong.
    max_tokens = 256,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new("gemini", config)
end

function H.openrouter_client(overrides)
  local config = {
    api_key = env.get("OPENROUTER_API_KEY"),
    -- Overridable: routed models come and go, and pinning one turns its
    -- retirement into a failure that looks like a library defect.
    model = env.get("OPENROUTER_MODEL") or "inception/mercury-2",
    -- Reasoning is spent from the output allowance, so a small budget can be
    -- consumed entirely before any content is produced.
    max_tokens = 256,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new("openrouter", config)
end

--- Factory for the providers that need no special configuration beyond a key.
--- The model is left unset so each one exercises its own documented default.
local function simple_client(provider, key_var, overrides)
  local config = {
    api_key = env.get(key_var),
    max_tokens = 64,
    temperature = 0,
    timeout = 30,
    retries = 0,
  }
  if overrides then
    for k, v in pairs(overrides) do config[k] = v end
  end
  return UGLuaLLM.new(provider, config)
end

function H.grok_client(overrides)
  return simple_client("grok", "GROK_API_KEY", overrides)
end

function H.groq_client(overrides)
  return simple_client("groq", "GROQ_API_KEY", overrides)
end

function H.mistral_client(overrides)
  return simple_client("mistral", "MISTRAL_API_KEY", overrides)
end

function H.deepseek_client(overrides)
  return simple_client("deepseek", "DEEPSEEK_API_KEY", overrides)
end

--- Prompt whose encoded request body comfortably exceeds a given size.
--- Used to cover the transport path for realistic multi-kilobyte requests.
function H.padded_prompt(instruction, bytes)
  local padding = string.rep("padding ", math.ceil((bytes or 2048) / 8))
  return instruction .. " Ignore the following padding: " .. padding
end

--- True when a failure is about the account rather than the library: no
--- credit, exhausted quota, or a temporarily unavailable model. Those must not
--- be reported as regressions, but every other error still has to fail loudly.
function H.is_account_problem(err, details)
  local status = details and details.status
  if status == 402 then return true end
  local text = tostring(err or ""):lower()
  local patterns = {
    "no credits", "insufficient", "quota", "billing",
    "exceeded your current", "payment required",
  }
  for _, pattern in ipairs(patterns) do
    if text:find(pattern, 1, true) then return true end
  end
  return false
end

--- True when the provider rejected the credential itself. Kept separate from
--- an account problem so the reason is visible in the report: a key that is
--- absent, expired or wrong means the provider was never exercised, which is
--- not the same as the library failing against it.
function H.is_credential_problem(err, details)
  local status = details and details.status
  local text = tostring(err or ""):lower()
  local patterns = {
    "incorrect api key", "invalid api key", "authentication fails",
    "invalid_api_key", "unauthorized", "no auth credentials",
    "api key is invalid", "is invalid",
  }
  for _, pattern in ipairs(patterns) do
    if text:find(pattern, 1, true) then return true end
  end
  -- 401 is unambiguous; 403 can also mean a disabled or region-blocked key.
  return status == 401 or status == 403
end

--- Reason to skip, or nil when the failure should be treated as a defect.
function H.unavailable_reason(err, details)
  if H.is_credential_problem(err, details) then
    return "credentials rejected (" ..
      tostring(details and details.status or "no status") .. ")"
  end
  if H.is_account_problem(err, details) then
    return "account cannot serve the request"
  end
  return nil
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
