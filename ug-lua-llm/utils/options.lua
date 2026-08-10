local Options = {}

-- Merge an explicit provider escape hatch into a generated payload. Generated
-- fields win, so callers cannot accidentally replace required protocol fields.
function Options.payload(base, options)
  local result = {}
  for key, value in pairs((options and options.request_options) or {}) do
    result[key] = value
  end
  for key, value in pairs(base or {}) do result[key] = value end
  return result
end

return Options
