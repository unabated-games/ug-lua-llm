package = "ug-lua-llm"
version = "0.1.0-1"
source = {
   url = "https://github.com/unabated-games/ug-lua-llm.git",
   tag = "v0.1.0"
}
description = {
   summary = "Unified Lua client for LLM APIs including OpenAI, Claude, Gemini, Grok, Groq, OpenRouter, Ollama, DeepSeek, and Mistral",
   detailed = [[
      ug-lua-llm provides a unified interface to interact with 9 AI/LLM providers:
      OpenAI (GPT models), Anthropic (Claude), Google (Gemini), xAI (Grok),
      Groq, OpenRouter, Ollama (local), DeepSeek, and Mistral.

      Features include chat/completion APIs, tool/function calling, real-time
      SSE streaming, embeddings, extended thinking (Claude and OpenAI o-series),
      normalized responses, rate limiting, exponential backoff with jitter,
      and configurable logging.
   ]],
   homepage = "https://github.com/unabated-games/ug-lua-llm",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1, < 5.5",
   "luasocket >= 3.0rc1-2",
   "dkjson >= 2.6",
   "http >= 0.4"
}
build = {
   type = "builtin",
   copy_directories = {
      "examples",
      "docs",
      "skills"
   },
   modules = {
      ["ug-lua-llm.conformance"] = "ug-lua-llm/conformance.lua",
      ["ug-lua-llm.doctor"] = "ug-lua-llm/doctor.lua",
      -- Main module
      ["ug-lua-llm"] = "ug-lua-llm/init.lua",

      -- Core modules
      ["ug-lua-llm.core.client"] = "ug-lua-llm/core/client.lua",
      ["ug-lua-llm.core.config"] = "ug-lua-llm/core/config.lua",
      ["ug-lua-llm.core.provider"] = "ug-lua-llm/core/provider.lua",
      ["ug-lua-llm.core.embeddings"] = "ug-lua-llm/core/embeddings.lua",
      ["ug-lua-llm.core.response"] = "ug-lua-llm/core/response.lua",
      ["ug-lua-llm.core.error"] = "ug-lua-llm/core/error.lua",

      -- Provider implementations
      ["ug-lua-llm.providers.openai_compatible"] = "ug-lua-llm/providers/openai_compatible.lua",
      ["ug-lua-llm.providers.openai"] = "ug-lua-llm/providers/openai.lua",
      ["ug-lua-llm.providers.claude"] = "ug-lua-llm/providers/claude.lua",
      ["ug-lua-llm.providers.grok"] = "ug-lua-llm/providers/grok.lua",
      ["ug-lua-llm.providers.groq"] = "ug-lua-llm/providers/groq.lua",
      ["ug-lua-llm.providers.openrouter"] = "ug-lua-llm/providers/openrouter.lua",
      ["ug-lua-llm.providers.gemini"] = "ug-lua-llm/providers/gemini.lua",
      ["ug-lua-llm.providers.ollama"] = "ug-lua-llm/providers/ollama.lua",
      ["ug-lua-llm.providers.deepseek"] = "ug-lua-llm/providers/deepseek.lua",
      ["ug-lua-llm.providers.mistral"] = "ug-lua-llm/providers/mistral.lua",

      -- Tools
      ["ug-lua-llm.tools.tool"] = "ug-lua-llm/tools/tool.lua",
      ["ug-lua-llm.tools.registry"] = "ug-lua-llm/tools/registry.lua",

      -- Utilities
      ["ug-lua-llm.utils.http"] = "ug-lua-llm/utils/http.lua",
      ["ug-lua-llm.utils.http_streaming"] = "ug-lua-llm/utils/http_streaming.lua",
      ["ug-lua-llm.utils.lifecycle"] = "ug-lua-llm/utils/lifecycle.lua",
      ["ug-lua-llm.utils.json"] = "ug-lua-llm/utils/json.lua",
      ["ug-lua-llm.utils.pagination"] = "ug-lua-llm/utils/pagination.lua",
      ["ug-lua-llm.utils.env"] = "ug-lua-llm/utils/env.lua",
      ["ug-lua-llm.utils.stream_helpers"] = "ug-lua-llm/utils/stream_helpers.lua",
      ["ug-lua-llm.utils.logger"] = "ug-lua-llm/utils/logger.lua",
      ["ug-lua-llm.utils.rate_limiter"] = "ug-lua-llm/utils/rate_limiter.lua",
      ["ug-lua-llm.utils.options"] = "ug-lua-llm/utils/options.lua",
      ["ug-lua-llm.utils.openai_chat_stream"] = "ug-lua-llm/utils/openai_chat_stream.lua",
   }
}
