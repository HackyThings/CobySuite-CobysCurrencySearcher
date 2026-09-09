---------------------------------------------------------------------------
-- CobySuite.Chat: branded chat output
--
-- Every consumer addon prints to chat with its own coloured prefix. This
-- constructor builds that printer once per addon:
--
--   local Message = CobySuite.Chat.NewMessenger({
--     prefix = "[Coby's Currency Searcher]",
--     color  = "F2C94C",          -- hex string, {r, g, b} (0..1) or a ColorMixin
--     gate   = function(verboseOnly) return not verboseOnly or IsVerbose() end,  -- optional
--   })
--   Message("Loaded.")             -- "[Coby's Currency Searcher] Loaded."
--   Message("Scanned 12 items", true)   -- second argument reaches opts.gate only
--
-- The gate lets an addon keep a "verbose" mode: return false to drop the
-- line. Without a gate every call prints.
---------------------------------------------------------------------------
CobySuite.Chat = CobySuite.Chat or {}
local Chat = CobySuite.Chat
local U = CobySuite.Utilities

local function ToHex(color)
  if type(color) == "string" then
    return color
  end
  if type(color) == "table" then
    local r = color.r or color[1] or 1
    local g = color.g or color[2] or 1
    local b = color.b or color[3] or 1
    return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
  end
  return "FFFFFF"
end

function Chat.NewMessenger(opts)
  opts = opts or {}
  local prefix = opts.prefix or ""
  if prefix ~= "" then
    prefix = U.WrapColor(ToHex(opts.color), prefix) .. (opts.separator or " ")
  end
  local gate = opts.gate
  return function(text, verboseOnly)
    if gate and not gate(verboseOnly) then return end
    print(prefix .. tostring(text))
  end
end
