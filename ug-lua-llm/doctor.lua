local Doctor = {}

local function capture(command)
  local pipe = io.popen(command .. " 2>&1")
  if not pipe then return nil end
  local output = pipe:read("*a")
  local ok = pipe:close()
  output = output:gsub("%s+$", "")
  return ok and output or nil, output
end

local function add(report, name, status, message, fix)
  report.checks[#report.checks + 1] = {
    name = name, status = status, message = message, fix = fix,
  }
  if status == "fail" then report.ok = false end
end

local function module_check(report, name, required, rock)
  local ok = pcall(require, name)
  add(report, "module:" .. name, ok and "pass" or (required and "fail" or "info"),
    ok and "available" or "not found",
    not ok and required and ("luarocks install " .. (rock or name)) or nil)
  return ok
end

local function lua_version()
  return (_VERSION or "Lua unknown"):match("(%d+%.%d+)") or "unknown"
end

function Doctor.run(options)
  options = options or {}
  local version = lua_version()
  local rocks = options.luarocks_command or os.getenv("UG_LUA_LLM_LUAROCKS_COMMAND") or
    "luarocks"
  local report = {
    ok = true,
    lua_version = version,
    package_path = package.path,
    package_cpath = package.cpath,
    offline = not options.endpoint,
    checks = {},
  }

  local executable = capture("command -v lua")
  report.lua_executable = executable or "unknown"
  add(report, "lua", "pass", (_VERSION or "Lua") .. " at " .. report.lua_executable)
  local numeric_version = tonumber(version)
  if not numeric_version or numeric_version < 5.1 or numeric_version >= 5.5 then
    add(report, "lua-supported", "fail",
      "ug-lua-llm currently supports Lua 5.1 through 5.4",
      "On Homebrew: brew install lua@5.4")
  else
    add(report, "lua-supported", "pass", "supported Lua version")
  end

  local rocks_version = capture(rocks .. " --version")
  if rocks_version then
    report.luarocks_version = rocks_version:match("[^\n]+")
    add(report, "luarocks", "pass", report.luarocks_version)
    local rocks_lua = capture(rocks .. " config lua_version")
    local rocks_trees = capture(rocks .. " config rocks_trees")
    report.luarocks_trees = rocks_trees
    add(report, "luarocks-trees", "info", rocks_trees or "unavailable")
    report.luarocks_lua_version = rocks_lua
    if rocks_lua and rocks_lua ~= version then
      add(report, "lua-version-match", "fail",
        "Lua is " .. version .. " but LuaRocks targets " .. rocks_lua,
        "Use `luarocks --lua-version " .. version .. " install ...`, then " ..
          "`eval \"$(luarocks path --lua-version " .. version .. ")\"`")
    else
      add(report, "lua-version-match", "pass",
        "Lua and LuaRocks both target " .. version)
    end
    local path_args = rocks == "luarocks" and
      (" --lua-version " .. version) or ""
    report.luarocks_path_command =
      "eval \"$(" .. rocks .. " path" .. path_args .. ")\""
    local user_root = rocks_trees and rocks_trees:match('root%s*=%s*"([^"]+)"')
    if user_root then
      local expected = user_root .. "/share/lua/" .. version
      local active = package.path:find(expected, 1, true) ~= nil
      local fix = not active and report.luarocks_path_command or nil
      add(report, "package-path", active and "pass" or "warn",
        active and (expected .. " is active") or (expected .. " is not active"), fix)
    end
  else
    add(report, "luarocks", "fail", "LuaRocks is not on PATH",
      "Install LuaRocks for Lua " .. version)
  end

  local socket_ok = module_check(report, "socket", true, "luasocket")
  local http_ok = module_check(report, "http.request", true, "http")
  local dkjson_ok = module_check(report, "dkjson", false, "dkjson")
  local cjson_ok = module_check(report, "cjson", false, "lua-cjson")
  if not dkjson_ok and not cjson_ok then
    add(report, "json", "fail", "No supported JSON backend found",
      "luarocks install dkjson")
  else
    add(report, "json", "pass", cjson_ok and "lua-cjson" or "dkjson")
  end

  if http_ok then
    local tls_ok = pcall(require, "http.tls")
    add(report, "tls", tls_ok and "pass" or "fail",
      tls_ok and "lua-http TLS support is available" or
        "lua-http is installed without a usable TLS backend",
      not tls_ok and "luarocks install luaossl" or nil)
  end

  if options.env_file then
    local env = require "ug-lua-llm.utils.env"
    local loaded, err = env.load(options.env_file)
    add(report, "env", loaded and "pass" or "fail",
      loaded and ("loaded " .. options.env_file) or tostring(err))
    local expected = options.api_key_env
    if not expected and options.provider then
      expected = ({ openai = "OPENAI_API_KEY", claude = "ANTHROPIC_API_KEY",
        gemini = "GEMINI_API_KEY", groq = "GROQ_API_KEY",
        grok = "GROK_API_KEY", openrouter = "OPENROUTER_API_KEY",
        deepseek = "DEEPSEEK_API_KEY", mistral = "MISTRAL_API_KEY" })
        [options.provider:lower()]
    end
    if expected then
      local configured = env.get(expected) ~= nil
      add(report, "credential", configured and "pass" or "warn",
        configured and (expected .. " is set") or (expected .. " is not set"))
    end
  end

  if options.endpoint and socket_ok and http_ok then
    local UGLuaLLM = require "ug-lua-llm"
    local client = UGLuaLLM.openai_compatible({
      base_url = options.endpoint,
      model = options.model or "doctor-check",
      api_key = options.api_key,
      capabilities = { streaming = false, tools = false },
      retries = 0,
      timeout = options.timeout or 10,
    })
    local models, err, details = client:list_models({ all_pages = false })
    add(report, "endpoint", models and "pass" or "fail",
      models and ("connected; received " .. #models .. " models") or tostring(err))
    if details then report.endpoint_error = details end
  end

  return report
end

function Doctor.print(report, output)
  output = output or io.stdout
  output:write("ug-lua-llm doctor\n")
  output:write("package.path:  " .. tostring(report.package_path) .. "\n")
  output:write("package.cpath: " .. tostring(report.package_cpath) .. "\n")
  for _, check in ipairs(report.checks) do
    output:write(string.format("%-18s %-5s %s\n",
      check.name, check.status:upper(), check.message or ""))
    if check.fix then output:write("  Fix: " .. check.fix .. "\n") end
  end
  return report.ok
end

return Doctor
