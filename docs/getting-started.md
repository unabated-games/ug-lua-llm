# Getting started

## Requirements

ug-lua-llm supports Lua 5.1 through 5.4. It uses LuaSocket, lua-http, and dkjson;
lua-cjson is an optional faster JSON backend.

Install it from LuaRocks:

```sh
luarocks install ug-lua-llm
```

To work against the source, or to try an unreleased change, install from a
checkout instead:

```sh
git clone https://github.com/unabated-games/ug-lua-llm.git
cd ug-lua-llm
luarocks make ug-lua-llm-0.2.0-1.rockspec
```

On macOS, Homebrew's unversioned Lua currently targets a newer Lua release than
ug-lua-llm supports. Install and select Lua 5.4 explicitly:

```sh
brew install lua@5.4 luarocks
export PATH="$(brew --prefix lua@5.4)/bin:$PATH"
eval "$(luarocks --lua-version 5.4 --lua-dir "$(brew --prefix lua@5.4)" path)"
```

If installed modules are not found, run `lua scripts/doctor.lua` from a source
checkout. It checks the active Lua and LuaRocks versions, module paths,
dependencies, JSON backend, and TLS support without printing secrets.

## First request

```lua
local llm = require "ug-lua-llm"

local client = llm.new("openai", {
  api_key = os.getenv("OPENAI_API_KEY"),
})

local response, err, details = client:chat({
  { role = "system", content = "Answer concisely." },
  { role = "user", content = "Why is Lua useful for embedded systems?" },
})

if not response then
  error(err .. (details and (" [" .. details.kind .. "]") or ""))
end

print(response.text)
```

Cloud providers require their API key. Local Ollama does not; continue with
[Local AI](guides/local-ai.md).

## The common response

Responses expose normalized fields where available:

- `text`: generated text
- `tool_calls`: normalized tool requests
- `usage`: prompt, completion, and total token counts
- `model`, `provider`, and `finish_reason`: request metadata
- `raw`: the untouched provider response

Methods return `result, err, details`. Existing callers may capture only the
first two values; `details` adds structured error handling when needed.
