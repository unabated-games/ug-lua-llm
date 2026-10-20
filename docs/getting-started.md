# Getting started

## Requirements

ug-lua-llm supports Lua 5.1 through 5.5. It uses LuaSocket, lua-http, and dkjson;
lua-cjson is an optional faster JSON backend. On Lua 5.5, install lua-http
first using the [Lua 5.5 steps](#lua-55) below.

Install it from LuaRocks:

```sh
luarocks install ug-lua-llm
```

To work against the source, or to try an unreleased change, install from a
checkout instead:

```sh
git clone https://github.com/unabated-games/ug-lua-llm.git
cd ug-lua-llm
luarocks make ug-lua-llm-0.4.1-1.rockspec
```

### Lua 5.5

ug-lua-llm runs on Lua 5.5, but two of lua-http's dependencies cannot yet be
installed there by LuaRocks alone:

- lua-http's rockspec requires `bit32`. Only Lua 5.1 uses it, and it has no
  Lua 5.5 release, so `luarocks install http` stops with *Could not satisfy
  dependency bit32*. lua-http itself works on 5.5 without it.
- cqueues cannot read Lua 5.5's version number from `lua.h`, so unless the
  headers are on the compiler's default search path its build fails with
  *'lua.h' file not found*.

Install lua-http's dependencies, then lua-http without dependency resolution,
then ug-lua-llm. If `luarocks install ug-lua-llm` has already failed with the
`bit32` error, run these as they are; anything it installed is reused.

```sh
luarocks install cqueues \
  CFLAGS="$(luarocks config variables.CFLAGS) -I$(luarocks config variables.LUA_INCDIR)"
for rock in compat53 luaossl basexx lpeg lpeg_patterns binaryheap fifo; do
  luarocks install "$rock"
done
luarocks install http --deps-mode=none
luarocks install ug-lua-llm
```

Homebrew's unversioned `lua` formula is Lua 5.5, and these steps work with it.
If LuaRocks targets another Lua by default, add `--lua-version 5.5` to each
`luarocks` command. To use Lua 5.4 instead, which needs none of this:

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
