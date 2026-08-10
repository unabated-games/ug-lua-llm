# Local AI and custom endpoints

## Ollama

Start Ollama and pull a model:

```sh
ollama pull llama3.2
```

Then create a client without an API key:

```lua
local llm = require "ug-lua-llm"

local client = llm.new("ollama", {
  model = "llama3.2",
  base_url = "http://localhost:11434/v1",
})

local response = assert(client:chat({
  { role = "user", content = "Explain this project in one sentence." },
}))
print(response.text)
```

Keep `/v1` on the URL. If the connection is refused, start Ollama or correct the
host. If the model is missing, pull the exact configured model. Tool, vision,
and structured-output support depend on the selected model and server version.

## Any OpenAI-compatible server

Use a custom endpoint without waiting for ug-lua-llm to add a named provider:

```lua
local client = require("ug-lua-llm").openai_compatible({
  base_url = "http://localhost:8000/v1",
  model = "my-model",
  api_key = os.getenv("LLM_API_KEY"), -- optional
  headers = { ["X-Tenant"] = "example" },
  capabilities = {
    streaming = true,
    tools = false,
    models = true,
  },
})
```

`base_url` and `model` are required. Authentication is optional. Capability
declarations default optimistically; set unsupported features to `false` to get
a clear local validation error before a request is sent.

Inspect configured support without making a request:

```lua
local capabilities = client:capabilities()
if capabilities.streaming then
  -- choose the streaming UI
end
```

To test the real server contract:

```sh
LLM_BASE_URL=http://localhost:11434/v1 \
LLM_MODEL=llama3.2 \
lua scripts/conformance.lua
```

Set `LLM_API_KEY` for bearer authentication. The runner checks model listing,
chat, and genuine SSE streaming only against the configured endpoint.
