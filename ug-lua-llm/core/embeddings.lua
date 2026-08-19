local HttpClient = require 'ug-lua-llm.utils.http'
local Config = require 'ug-lua-llm.core.config'
local Error = require 'ug-lua-llm.core.error'

local Embeddings = {}

-- Default endpoint per provider, mirroring the chat clients. Without these a
-- caller had to supply base_url even for a provider the library already knows,
-- and omitting it failed while building the URL rather than with a useful
-- message.
-- Each service names its own embedding model, and the OpenAI-compatible
-- adapter serves several of them. Falling back to one hardcoded OpenAI name
-- meant Mistral was asked for a model it has never had -- 400 -- while the
-- Gemini default had been retired outright: 404, for anyone who did not pass a
-- model. Defaults age out silently and only fail the users who did not set one.
local DEFAULT_EMBEDDING_MODEL = {
  openai = "text-embedding-3-small",
  mistral = "mistral-embed",
  gemini = "gemini-embedding-001",
  ollama = "nomic-embed-text",
}

-- How each service spells the requested vector width. Sending OpenAI's name to
-- the others left the option silently doing nothing.
local DIMENSIONS_FIELD = {
  openai = "dimensions",
  mistral = "output_dimension",
}

local DEFAULT_BASE_URL = {
  openai = "https://api.openai.com/v1",
  ollama = "http://localhost:11434/v1",
  mistral = "https://api.mistral.ai/v1",
  deepseek = "https://api.deepseek.com/v1",
  gemini = "https://generativelanguage.googleapis.com/v1beta",
}

-- Provider-specific adapters
local adapters = {}

local function response_error(config, response)
  local message = "Embeddings request failed with status " .. tostring(response.status)
  local body = response.body
  if type(body) == "table" and body.error then
    message = type(body.error) == "table" and
      body.error.message or tostring(body.error)
  end
  return message, Error.http(config.provider_name, response, message)
end

-- OpenAI-compatible adapter (works for OpenAI, Mistral, Ollama, DeepSeek)
adapters.openai = {
  embed = function(http, config, input, options)
    options = options or {}
    local url = config.base_url .. "/embeddings"

    local payload = {
      model = options.model or config.embedding_model or
        DEFAULT_EMBEDDING_MODEL[config.provider_name] or "text-embedding-3-small",
      input = input,
    }

    if options.dimensions then
      payload[DIMENSIONS_FIELD[config.provider_name] or "dimensions"] =
        options.dimensions
    end

    local response, err, details = http:post(url, payload)
    if err or not response then
      return nil, err or "Embeddings request failed", details or
        Error.transport(config.provider_name, err or "Embeddings request failed")
    end

    if response.status ~= 200 then
      return nil, response_error(config, response)
    end

    -- Normalize response. The API documents that results may arrive out of
    -- order, so pair by the index it reports rather than by arrival: a caller
    -- lining embeddings[i] up with inputs[i] would otherwise get the wrong
    -- vector for the wrong text, with nothing to indicate it.
    local embeddings = {}
    if response.body and response.body.data then
      for _, item in ipairs(response.body.data) do
        table.insert(embeddings, {
          embedding = item.embedding,
          index = item.index,
        })
      end
      table.sort(embeddings, function(a, b)
        return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
      end)
    end

    return {
      embeddings = embeddings,
      model = response.body.model,
      usage = response.body.usage,
    }
  end
}

-- Gemini adapter
adapters.gemini = {
  embed = function(http, config, input, options)
    options = options or {}
    local model = options.model or config.embedding_model or
      DEFAULT_EMBEDDING_MODEL.gemini

    -- Gemini expects a single text or batch
    local texts = type(input) == "table" and input or { input }
    local url = string.format(
      "%s/models/%s:batchEmbedContents",
      config.base_url or "https://generativelanguage.googleapis.com/v1beta",
      model
    )

    local requests = {}
    for _, text in ipairs(texts) do
      local request = {
        model = "models/" .. model,
        content = { parts = { { text = text } } },
      }
      -- Gemini takes the width per request, spelled its own way.
      if options.dimensions then
        request.outputDimensionality = options.dimensions
      end
      table.insert(requests, request)
    end

    local payload = { requests = requests }

    local response, err, details = http:post(url, payload)
    if err or not response then
      return nil, err or "Embeddings request failed", details or
        Error.transport(config.provider_name, err or "Embeddings request failed")
    end

    if response.status ~= 200 then
      return nil, response_error(config, response)
    end

    local embeddings = {}
    if response.body and response.body.embeddings then
      for i, item in ipairs(response.body.embeddings) do
        table.insert(embeddings, {
          embedding = item.values,
          index = i - 1,
        })
      end
    end

    return {
      embeddings = embeddings,
      model = model,
    }
  end
}

-- Alias providers that use the OpenAI-compatible format. DeepSeek is
-- deliberately absent: it serves no embeddings endpoint at all, and aliasing it
-- here produced a bare 404 that read like a misconfiguration rather than a
-- service that does not offer the feature.
adapters.mistral = adapters.openai
adapters.ollama = adapters.openai

-- Create a new Embeddings client
function Embeddings.new(provider_name, config)
  config = config or {}
  local resolved_config = Config.new(config)
  resolved_config.provider_name = provider_name
  resolved_config.base_url = resolved_config.base_url or
    DEFAULT_BASE_URL[provider_name]

  local http = HttpClient.new(resolved_config)

  -- Set up auth headers based on provider
  if resolved_config.api_key then
    if provider_name == "gemini" then
      http.headers["x-goog-api-key"] = resolved_config.api_key
    elseif provider_name == "claude" then
      http.headers["x-api-key"] = resolved_config.api_key
    else
      http.headers["Authorization"] = "Bearer " .. resolved_config.api_key
    end
  end

  local adapter = adapters[provider_name]
  if not adapter then
    error("Embeddings are not available for provider: " ..
      tostring(provider_name) ..
      ". Providers with embeddings: openai, gemini, mistral, ollama.")
  end
  if not resolved_config.base_url then
    error("Embeddings require a base_url for provider: " ..
      tostring(provider_name))
  end

  -- Accept both `embeddings:embed(input)` and `embeddings.embed(input)`. The
  -- rest of the library is called with a colon, so the documentation and the
  -- agent reference both use that form, but this object was dot-only: a colon
  -- call passed the object itself as the input and failed while encoding the
  -- request. Detect the receiver and shift the arguments.
  -- `http` is exposed, and read at call time, so the transport can be replaced
  -- the same way it can on a provider.
  local api = { provider = provider_name, http = http, config = resolved_config }

  api.embed = function(first, second, third)
    local input, options = first, second
    if first == api then input, options = second, third end
    return adapter.embed(api.http, resolved_config, input, options)
  end

  return api
end

return Embeddings
