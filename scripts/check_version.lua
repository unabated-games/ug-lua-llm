-- Verify that everything carrying the version agrees.
--
-- A release moves four things in step: the rockspec filename, its `version`
-- field, its `source.tag`, and the library's `_VERSION`. A mismatch in the
-- first three is not caught by any test, and `source.tag` is the dangerous
-- one: LuaRocks builds the source rock from whatever that tag points at, so a
-- stale value publishes the wrong code under the right version number.
--
-- Usage: lua scripts/check_version.lua [rockspec]
--        With no argument the single rockspec in the working directory is used.

local function find_rockspec()
  local matches = {}
  -- io.popen keeps this dependency-free; the pattern is fixed, not user input.
  local listing = io.popen("ls *.rockspec 2>/dev/null")
  if listing then
    for name in listing:lines() do matches[#matches + 1] = name end
    listing:close()
  end
  if #matches == 0 then error("no rockspec found in the working directory") end
  if #matches > 1 then
    error("expected exactly one rockspec, found " .. #matches ..
      ": " .. table.concat(matches, ", "))
  end
  return matches[1]
end

local rockspec_path = arg[1] or find_rockspec()

local file = assert(io.open(rockspec_path, "r"),
  "cannot open rockspec: " .. rockspec_path)
local source = file:read("*a")
file:close()

local failures = {}
local function check(ok, message)
  if not ok then failures[#failures + 1] = message end
end

local package_name = assert(source:match('\npackage%s*=%s*"([^"]+)"') or
  source:match('^package%s*=%s*"([^"]+)"'), "rockspec did not define package")
local rock_version = assert(source:match('\nversion%s*=%s*"([^"]+)"'),
  "rockspec did not define version")
local base_version = rock_version:match("^([^-]+)")
local source_tag = source:match('tag%s*=%s*"([^"]+)"')

-- 1. The filename has to match package and version, or `luarocks upload` and
--    the release workflow will not find it.
local expected_name = package_name .. "-" .. rock_version .. ".rockspec"
local actual_name = rockspec_path:match("([^/]+)$")
check(actual_name == expected_name,
  string.format("filename mismatch: %s should be %s", actual_name, expected_name))

-- 2. The library reports the same version it is packaged as.
local library_version = require("ug-lua-llm")._VERSION
check(base_version == library_version,
  string.format("version mismatch: rockspec=%s runtime=%s",
    base_version, library_version))

-- 3. source.tag points at this release. This is the check that matters most:
--    nothing else notices when it is left behind.
if source_tag then
  local expected_tag = "v" .. base_version
  check(source_tag == expected_tag,
    string.format("source.tag mismatch: %s should be %s (a stale tag " ..
      "publishes the wrong source under this version)", source_tag, expected_tag))
else
  check(false, "rockspec source has no tag; a release must pin one")
end

-- 4. Every module on disk is packaged. A new file that nobody adds to
--    build.modules is absent from an installed rock, so `require` fails for
--    users while every test that runs from the source tree still passes.
local listing = io.popen("find ug-lua-llm -name '*.lua' 2>/dev/null")
if listing then
  local missing = {}
  for path in listing:lines() do
    if not source:find(path, 1, true) then
      missing[#missing + 1] = path
    end
  end
  listing:close()
  if #missing > 0 then
    table.sort(missing)
    check(false, "not listed in build.modules, so they would be missing from " ..
      "an installed rock: " .. table.concat(missing, ", "))
  end
end

if #failures > 0 then
  io.stderr:write("Version consistency failed for " .. rockspec_path .. ":\n")
  for _, message in ipairs(failures) do
    io.stderr:write("  - " .. message .. "\n")
  end
  os.exit(1)
end

print(string.format(
  "version %s is consistent (%s, tag %s, runtime %s)",
  base_version, actual_name, source_tag, library_version))
