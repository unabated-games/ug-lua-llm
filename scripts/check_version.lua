local rockspec_path = assert(arg[1], "rockspec path is required")
local file = assert(io.open(rockspec_path, "r"))
local source = file:read("*a")
file:close()
local rock_version = assert(source:match('\nversion%s*=%s*"([^"]+)"'),
  "rockspec did not define version"):match("^([^-]+)")
local library_version = require("ug-lua-llm")._VERSION
assert(rock_version == library_version,
  string.format("version mismatch: rockspec=%s runtime=%s", rock_version, library_version))
print("version " .. library_version .. " is consistent")
