-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Logger: thin wrapper around CobySuite.Debug.NewLogger
-------------------------------------------------------------------------------

CobysCurrencySearcher.Debug = CobySuite.Debug.NewLogger({
  addonName = "CobysCurrencySearcher",
  categories = {
    "INIT", "CONFIG", "SEARCH", "FAVORITES", "DIAG",
  },
  savedVariable = "COBYS_CURRENCY_SEARCHER_DEBUG_LOG",
  sessionHeader = function(lines)
    CobySuite.Debug.AppendConfigSnapshot(lines, "COBYS_CURRENCY_SEARCHER_CONFIG")
  end,
})
