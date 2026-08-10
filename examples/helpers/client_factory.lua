-- Helper module for creating LLM clients across examples
-- Eliminates boilerplate code and provides command-line switching capability

local UGLuaLLM = require "ug-lua-llm"
local env = require "ug-lua-llm.utils.env"

local ClientFactory = {}

-- Provider configurations with default models
local PROVIDER_CONFIGS = {
  openai = {
    env_key = "OPENAI_API_KEY",
    default_model = "gpt-5.6-luna",
    description = "OpenAI (GPT models)"
  },
  claude = {
    env_key = "CLAUDE_API_KEY",
    default_model = "claude-haiku-4-5-20251001",
    description = "Anthropic Claude"
  },
  groq = {
    env_key = "GROQ_API_KEY",
    default_model = "llama-3.3-70b-versatile",
    description = "Groq (Llama, Mixtral models)"
  },
  grok = {
    env_key = "GROK_API_KEY",
    default_model = "grok-2-1212",
    description = "Grok"
  },
  openrouter = {
    env_key = "OPENROUTER_API_KEY",
    default_model = "~openai/gpt-latest",
    description = "OpenRouter (access to 50+ models)"
  }
}

-- Parse command line arguments
function ClientFactory.parse_args()
  local args = {}
  
  -- Set defaults
  args.provider = nil
  args.model = nil
  args.temperature = 0.7
  args.show_help = false
  
  local i = 1
  while i <= #arg do
    local arg_val = arg[i]
    
    if arg_val == "--help" or arg_val == "-h" then
      args.show_help = true
    elseif arg_val == "--provider" or arg_val == "-p" then
      args.provider = arg[i + 1]
      i = i + 1
    elseif arg_val == "--model" or arg_val == "-m" then
      args.model = arg[i + 1]
      i = i + 1
    elseif arg_val == "--temperature" or arg_val == "-t" then
      args.temperature = tonumber(arg[i + 1]) or 0.7
      i = i + 1
    elseif arg_val:sub(1, 1) == "-" then
      -- Unknown option, just skip it and its potential value
      if i < #arg and arg[i + 1]:sub(1, 1) ~= "-" then
        i = i + 1
      end
    end
    
    i = i + 1
  end
  
  return args
end

-- Display help information
function ClientFactory.show_help()
  print("Usage: lua script.lua [options]")
  print("\nOptions:")
  print("  -h, --help                  Show this help message")
  print("  -p, --provider PROVIDER     Specify the LLM provider to use")
  print("  -m, --model MODEL           Specify the model to use")
  print("  -t, --temperature TEMP      Set temperature (0.0-1.0, default: 0.7)")
  
  print("\nAvailable providers:")
  for name, config in pairs(PROVIDER_CONFIGS) do
    print(string.format("  %-12s %s (default model: %s)", 
                       name, config.description, config.default_model))
  end
  
  print("\nExample:")
  print("  lua script.lua --provider openai --model gpt-5.6-terra")
  print("  lua script.lua -p claude -t 0.5")
  
  os.exit(0)
end

-- Load environment variables and create a client
function ClientFactory.create_client(options)
  options = options or {}
  
  -- Parse command line arguments
  local args = ClientFactory.parse_args()
  
  -- Show help if requested
  if args.show_help then
    ClientFactory.show_help()
  end
  
  -- Load environment variables from .env file
  local env_path = options.env_path or ".env"
  local _, err = env.load(env_path)
  if err then
    print("Warning: " .. err)
    print("Using environment variables from system instead.")
  end
  
  -- Determine the provider to use (command line > options > auto-detect)
  local provider_name = args.provider or options.provider
  local available_providers = {}
  
  -- Check which providers have API keys
  for name, config in pairs(PROVIDER_CONFIGS) do
    local api_key = env.get(config.env_key)
    if api_key then
      table.insert(available_providers, name)
      
      -- If no provider specified, use the first one with an API key
      if not provider_name then
        provider_name = name
      end
    end
  end
  
  -- Check if we have any available providers
  if #available_providers == 0 then
    print("Error: No API keys found. Please set them in .env file or as environment variables.")
    print("Required environment variables:")
    for _, config in pairs(PROVIDER_CONFIGS) do
      print("  " .. config.env_key)
    end
    os.exit(1)
  end
  
  -- Validate provider selection
  if provider_name and not PROVIDER_CONFIGS[provider_name] then
    print("Error: Invalid provider '" .. provider_name .. "'")
    print("Available providers: " .. table.concat(available_providers, ", "))
    os.exit(1)
  end
  
  -- Get API key for selected provider
  local config = PROVIDER_CONFIGS[provider_name]
  local api_key = env.get(config.env_key)
  
  if not api_key then
    print("Error: No API key found for provider '" .. provider_name .. "'")
    print("Please set " .. config.env_key .. " in your .env file or environment variables")
    print("Available providers: " .. table.concat(available_providers, ", "))
    os.exit(1)
  end
  
  -- Determine model to use (command line > options > default)
  local model = args.model or options.model or config.default_model
  
  -- Create the client
  local client = UGLuaLLM.new(provider_name, {
    api_key = api_key,
    model = model,
    temperature = args.temperature or options.temperature or 0.7
  })
  
  -- Return client and provider info
  return {
    client = client,
    provider = provider_name,
    model = model,
    temperature = args.temperature or options.temperature or 0.7
  }
end

return ClientFactory
