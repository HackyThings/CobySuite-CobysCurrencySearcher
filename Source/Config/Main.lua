local Config = CobysCurrencySearcher.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New
---------------------------------------------------------------------------
local base = CobySuite.Config.New({
  savedVariable = "COBYS_CURRENCY_SEARCHER_CONFIG",
  options = {
    MATCH_DESCRIPTIONS = "match_descriptions",
  },
  defaults = {
    ["match_descriptions"] = false,
  },
  debug = CobysCurrencySearcher.Debug,
  onSet = function(name, old, value)
    CobysCurrencySearcher.EventBus:Fire(CobysCurrencySearcher.Events.ConfigChanged, name, value, old)
  end,
  onReset = function()
    CobysCurrencySearcher.EventBus:Fire(CobysCurrencySearcher.Events.ConfigChanged)
  end,
})

-- Install onto the CobysCurrencySearcher.Config namespace
Config.Options       = base.Options
Config.Defaults      = base.Defaults
Config.IsValidOption = base.IsValidOption
Config.Get           = base.Get
Config.Set           = base.Set
Config.Reset         = base.Reset

---------------------------------------------------------------------------
-- InitializeData: wraps base with addon-specific SavedVariable init
---------------------------------------------------------------------------
function Config.InitializeData()
  base.InitializeData()

  if COBYS_CURRENCY_SEARCHER_WINDOW_STATE == nil then
    COBYS_CURRENCY_SEARCHER_WINDOW_STATE = {}
  end
end
