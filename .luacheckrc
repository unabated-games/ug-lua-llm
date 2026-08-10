-- luacheck configuration
unused_args = false
max_line_length = false

-- Allow underscore-prefixed variables to be unused
ignore = {"21./_.*"}

-- Busted test globals
files["spec/**/*_spec.lua"] = {
  globals = {"describe", "it", "before_each", "after_each", "setup", "teardown", "pending", "spy", "stub", "mock", "assert"}
}

