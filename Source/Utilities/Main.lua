local Utilities = CobysCurrencySearcher.Utilities

---------------------------------------------------------------------------
-- Addon-specific: chat output (branded prefix)
---------------------------------------------------------------------------
Utilities.Message = CobySuite_CobysCurrencySearcher.Chat.NewMessenger({
  prefix = "[Coby's Currency Searcher]",
  color = CobysCurrencySearcher.BRAND_COLOR,
})
