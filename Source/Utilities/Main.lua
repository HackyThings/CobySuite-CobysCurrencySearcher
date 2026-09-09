local Utilities = CobysCurrencySearcher.Utilities

---------------------------------------------------------------------------
-- Addon-specific: chat output (branded prefix)
---------------------------------------------------------------------------
Utilities.Message = CobySuite.Chat.NewMessenger({
  prefix = "[Coby's Currency Searcher]",
  color = CobysCurrencySearcher.BRAND_COLOR,
})
