-------------------------------------------------------------------------------
-- CobysCurrencySearcher Debug Window: thin wrapper around CobySuite.Debug.NewWindow
-------------------------------------------------------------------------------

CobysCurrencySearcher.DebugWindow = CobySuite_CobysCurrencySearcher.Debug.NewWindow({
  windowName = "CobysCurrencySearcherDebugWindow",
  title = CobySuite_CobysCurrencySearcher.Utilities.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " debug log",
  icon = CobysCurrencySearcher.ICON,
  logger = CobysCurrencySearcher.Debug,
})
