-- Pure base64 encoder. Used by the utils shim (utils.base64_encode).
local b64 = {}
local A = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function b64.encode(data)
  local out = {}
  local n = #data
  local i = 1
  while i <= n do
    local b1 = data:byte(i)
    local b2 = (i + 1 <= n) and data:byte(i + 1) or nil
    local b3 = (i + 2 <= n) and data:byte(i + 2) or nil
    local n1 = b1 >> 2
    local n2 = ((b1 & 0x03) << 4) | ((b2 or 0) >> 4)
    local n3 = b2 and (((b2 & 0x0F) << 2) | ((b3 or 0) >> 6)) or nil
    local n4 = b3 and (b3 & 0x3F) or nil
    out[#out + 1] = A:sub(n1 + 1, n1 + 1)
    out[#out + 1] = A:sub(n2 + 1, n2 + 1)
    out[#out + 1] = n3 and A:sub(n3 + 1, n3 + 1) or "="
    out[#out + 1] = n4 and A:sub(n4 + 1, n4 + 1) or "="
    i = i + 3
  end
  return table.concat(out)
end

local DECODE = {}
for i = 1, #A do DECODE[A:sub(i, i)] = i - 1 end

-- decode(text) -> raw bytes, or nil for malformed input. Uploads use this
-- instead of passing binary strings through JSON/CDP, which must remain UTF-8.
function b64.decode(text)
  if type(text) ~= "string" then return nil end
  if text == "" then return "" end
  if #text % 4 ~= 0 or text:find("[^A-Za-z0-9+/=]") then return nil end
  local out = {}
  for i = 1, #text, 4 do
    local c1, c2, c3, c4 = text:sub(i, i), text:sub(i + 1, i + 1),
      text:sub(i + 2, i + 2), text:sub(i + 3, i + 3)
    local n1, n2 = DECODE[c1], DECODE[c2]
    local n3, n4 = c3 == "=" and nil or DECODE[c3], c4 == "=" and nil or DECODE[c4]
    if n1 == nil or n2 == nil or (c3 ~= "=" and n3 == nil)
        or (c4 ~= "=" and n4 == nil) then return nil end
    if c3 == "=" and c4 ~= "=" then return nil end
    if (c3 == "=" or c4 == "=") and i + 3 ~= #text then return nil end
    out[#out + 1] = string.char((n1 << 2) | (n2 >> 4))
    if n3 ~= nil then
      out[#out + 1] = string.char(((n2 & 0x0f) << 4) | (n3 >> 2))
    end
    if n4 ~= nil then
      out[#out + 1] = string.char(((n3 & 0x03) << 6) | n4)
    end
  end
  return table.concat(out)
end

return b64
