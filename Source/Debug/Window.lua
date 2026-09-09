-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

CobysCurrencySearcher.DebugWindow = CobySuite.Debug.NewWindow({
  windowName = "CobysCurrencySearcherDebugWindow",
  title = "Coby's Currency Searcher Debug Log",
  logger = CobysCurrencySearcher.Debug,
})
