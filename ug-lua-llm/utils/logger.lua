local Logger = {}

local LEVELS = {
  ERROR = 1,
  WARN  = 2,
  INFO  = 3,
  DEBUG = 4,
  TRACE = 5,
}

Logger.LEVELS = LEVELS

local LEVEL_NAMES = {}
for name, val in pairs(LEVELS) do
  LEVEL_NAMES[val] = name
end

-- Module-level defaults (disabled by default)
local current_level = nil  -- nil means logging is disabled
local redact_payloads = true
local output_fn = function(msg) io.stderr:write(msg .. "\n") end

function Logger.set_level(level)
  if type(level) == "string" then
    level = LEVELS[level:upper()]
  end
  current_level = level
end

function Logger.disable()
  current_level = nil
end

function Logger.set_redact_payloads(enabled)
  redact_payloads = enabled
end

function Logger.set_output(fn)
  output_fn = fn
end

local function log(level, fmt, ...)
  if not current_level or level > current_level then
    return
  end
  local prefix = "[" .. (LEVEL_NAMES[level] or "?") .. "] "
  local msg = prefix .. string.format(fmt, ...)
  output_fn(msg)
end

function Logger.error(fmt, ...) log(LEVELS.ERROR, fmt, ...) end
function Logger.warn(fmt, ...)  log(LEVELS.WARN,  fmt, ...) end
function Logger.info(fmt, ...)  log(LEVELS.INFO,  fmt, ...) end
function Logger.debug(fmt, ...) log(LEVELS.DEBUG, fmt, ...) end
function Logger.trace(fmt, ...) log(LEVELS.TRACE, fmt, ...) end

function Logger.is_enabled(level)
  if type(level) == "string" then
    level = LEVELS[level:upper()]
  end
  return current_level ~= nil and level <= current_level
end

function Logger.redact(value)
  if redact_payloads then
    return "[REDACTED]"
  end
  return tostring(value)
end

return Logger
