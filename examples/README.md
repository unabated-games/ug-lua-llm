# ug-lua-llm examples

Run examples from the project root. They load API keys from the root `.env` file and automatically use the first configured provider. Pass `--provider` or `--model` to override that choice.

```bash
lua examples/basic_chat.lua
lua examples/streaming_chat.lua --provider claude "Tell me a joke"
lua examples/conversation_chat.lua --provider claude --temperature 0.5
lua examples/tool_calling.lua --provider claude
lua examples/ollama_chat.lua llama3.2 "Why use local AI?"
lua examples/custom_endpoint.lua
```

Use `--help` with any example that uses the shared client factory.

## Examples

- **basic_chat.lua** — One non-streaming request using the normalized `response.text` field.
- **streaming_chat.lua** — Streams one response as text arrives.
- **conversation_chat.lua** — Interactive multi-turn chat with message history.
- **tool_calling.lua** — Registers and executes one local tool, then requests the final answer.
- **tool_registry_example.lua** — Advanced registry, custom-tool, and collection features.
- **structured_output.lua** — Requests a JSON Schema and reads the decoded object from `response.parsed`.
- **reasoning_control.lua** — Compares default, minimized, and raised reasoning, with the token cost of each.
- **ollama_chat.lua** — One local, non-streaming Ollama request.
- **ollama_streaming.lua** — Streams from a selected local Ollama model.
- **ollama_tool_calling.lua** — Runs a local tool with a tool-capable Ollama model.
- **custom_endpoint.lua** — Connects to an arbitrary OpenAI-compatible server.

The `helpers/` directory contains the shared provider and command-line setup used by these scripts.

## Configuration

Create `.env` in the project root with one or more keys:

```dotenv
OPENAI_API_KEY=your-openai-api-key
CLAUDE_API_KEY=your-anthropic-api-key
GROQ_API_KEY=your-groq-api-key
GROK_API_KEY=your-xai-api-key
OPENROUTER_API_KEY=your-openrouter-api-key
OPENAI_COMPATIBLE_BASE_URL=http://localhost:8000/v1
OPENAI_COMPATIBLE_MODEL=your-model-name
# OPENAI_COMPATIBLE_API_KEY=optional-key
```

Do not commit `.env`; use `.env.example` as a safe template.

## Running locally with Ollama

Install and start Ollama, then download the model used by the examples:

```bash
ollama pull llama3.2
lua examples/ollama_chat.lua
lua examples/ollama_streaming.lua
lua examples/ollama_tool_calling.lua
```

Pass a different installed model as the first argument. Set
`OLLAMA_BASE_URL` when Ollama is on another host; include the OpenAI-compatible
`/v1` suffix.

If a request is refused, check that Ollama is running. If the API reports that
a model is missing, run `ollama pull <model>`. Tool support depends on the
selected model; a server being OpenAI-compatible does not imply that every
model implements tools, vision, structured output, or every request option.
