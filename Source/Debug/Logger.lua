-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Logger: thin wrapper around CobySuite.Debug.NewLogger
-------------------------------------------------------------------------------

CobysCurrencySearcher.Debug = CobySuite_CobysCurrencySearcher.Debug.NewLogger({
  addonName = "CobysCurrencySearcher",
  categories = {
    "INIT", "CONFIG", "SEARCH", "FAVORITES", "DIAG",
  },
  savedVariable = "COBYS_CURRENCY_SEARCHER_DEBUG_LOG",
  sessionHeader = function(lines)
    CobySuite_CobysCurrencySearcher.Debug.AppendConfigSnapshot(lines, "COBYS_CURRENCY_SEARCHER_CONFIG")
  end,
})
