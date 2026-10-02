-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

CobysCurrencySearcher.DebugWindow = CobySuite_CobysCurrencySearcher.Debug.NewWindow({
  windowName = "CobysCurrencySearcherDebugWindow",
  title = "Coby's Currency Searcher Debug Log",
  icon = CobysCurrencySearcher.ICON,
  logger = CobysCurrencySearcher.Debug,
})
