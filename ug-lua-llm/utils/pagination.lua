local url = require "socket.url"

local Pagination = {}

function Pagination.query(base, params)
  local parts = {}
  for key, value in pairs(params or {}) do
    if value ~= nil then
      parts[#parts + 1] = url.escape(tostring(key)) .. "=" ..
        url.escape(tostring(value))
    end
  end
  table.sort(parts)
  if #parts == 0 then return base end
  return base .. (base:find("?", 1, true) and "&" or "?") .. table.concat(parts, "&")
end

function Pagination.openai(fetch, base_url, options)
  options = options or {}
  local items, after = {}, options.after
  local max_pages = options.all_pages == false and 1 or (options.max_pages or 100)
  for _ = 1, max_pages do
    local response, err, details = fetch(Pagination.query(base_url, {
      after = after,
      limit = options.page_size,
    }))
    if not response then return nil, err, details end
    local body = response.body or {}
    for _, item in ipairs(body.data or {}) do items[#items + 1] = item end
    if not body.has_more then return items end
    local data = body.data or {}
    local last = data[#data]
    local next_after = body.next or body.next_cursor or body.last_id or
      (last and last.id)
    if not next_after or next_after == after then return items end
    after = next_after
  end
  return items
end

return Pagination
