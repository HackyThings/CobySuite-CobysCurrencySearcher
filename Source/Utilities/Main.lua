local Utilities = CobysCurrencySearcher.Utilities
local U = CobySuite.Utilities

---------------------------------------------------------------------------
-- Addon-specific: chat output (branded prefix)
---------------------------------------------------------------------------
function Utilities.Message(message)
  print(U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "[Coby's Currency Searcher]") .. " " .. message)
end
