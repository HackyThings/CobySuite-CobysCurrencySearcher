CobysCurrencySearcher = {
  Debug = {},
  Config = {},
  Utilities = {},
}

CobysCurrencySearcher.BRAND_COLOR = "F2C94C"

-------------------------------------------------------------------------------
-- EventBus event constants
-------------------------------------------------------------------------------
CobysCurrencySearcher.Events = {
  ConfigChanged = "cobys_currency_searcher_config_changed",
}

-------------------------------------------------------------------------------
-- Addon metadata
-------------------------------------------------------------------------------
local ADDON_NAME = "CobysCurrencySearcher"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0.0"

-------------------------------------------------------------------------------
-- Slash commands
--
-- Registered through CobySuite.Slash, which generates help and version.
-- Anything that is not a command is a search query (fallback).
-------------------------------------------------------------------------------
CobySuite.Slash.Register({
  key = "COBYSCURRENCYSEARCHER",
  slashes = { "/ccs", "/cobyscurrencysearcher" },
  title = "Coby's Currency Searcher",
  version = VERSION,
  message = function(text) CobysCurrencySearcher.Utilities.Message(text) end,
  commands = {
    { usage = "<text>", help = "Open the Currency tab and search for <text>" },
    {
      name = "settings", aliases = { "config", "show" }, help = "Open the settings window",
      run = function()
        if CobysCurrencySearcher.Config.ToggleSettings then
          CobysCurrencySearcher.Config.ToggleSettings()
        end
      end,
    },
    {
      name = "debug", help = "Toggle the debug window",
      run = function()
        if CobysCurrencySearcher.DebugWindow then
          CobysCurrencySearcher.DebugWindow:Toggle()
        end
      end,
    },
  },
  fallback = function(input)
    -- Anything else is a search query: open the Currency tab and search it.
    if CobysCurrencySearcher.Search and CobysCurrencySearcher.Search.OpenAndSearch then
      CobysCurrencySearcher.Search.OpenAndSearch(input)
    end
  end,
})

-------------------------------------------------------------------------------
-- Startup sequence
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
  if CobysCurrencySearcher.Config.InitializeData then
    CobysCurrencySearcher.Config.InitializeData()
  end
  CobysCurrencySearcher.Debug.Log("INIT", "Coby's Currency Searcher v%s loaded", VERSION)
end)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  CobysCurrencySearcher.Debug.Log("INIT", "PLAYER_LOGIN complete")
end)
