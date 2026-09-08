-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

CobySuite.Debug.NewWindow({
  windowName = "CobysCurrencySearcherDebugWindow",
  title = "Coby's Currency Searcher Debug Log",
  logger = CobysCurrencySearcher.Debug,
})
