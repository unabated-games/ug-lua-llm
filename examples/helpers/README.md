# Example Helpers

This directory contains helper utilities for the Lua-LLM examples.

## ClientFactory

The `client_factory.lua` module eliminates boilerplate code in the examples by providing a consistent way to create LLM clients with support for command-line options.

### Features

- Automatic detection of available API keys
- Command-line provider selection (`--provider`)
- Command-line model selection (`--model`)
- Command-line temperature adjustment (`--temperature`)
- Helpful error messages
- Built-in help (`--help`)

### Usage

```lua
local ClientFactory = require "examples.helpers.client_factory"

-- Create a client using the ClientFactory
local result = ClientFactory.create_client()
local client = result.client
local provider_name = result.provider
local model_name = result.model
local temperature = result.temperature

-- Use the client
client:chat(messages)
```

### Command-line Example

```bash
# Use OpenAI with GPT-4
lua your_script.lua --provider openai --model gpt-5.6-terra

# Use Claude with custom temperature
lua your_script.lua --provider claude --temperature 0.3

# Show all options and providers
lua your_script.lua --help
```

### Customization

You can provide default options to the `create_client` function:

```lua
local result = ClientFactory.create_client({
  provider = "openai",
  model = "gpt-5.6-luna",
  temperature = 0.5,
  env_path = "/path/to/custom/.env"
})
```

Command-line options will override these defaults, following this precedence:
1. Command-line options (`--provider`, `--model`, etc.)
2. Options passed to `create_client()`
3. Auto-detected values and defaults
