local Config = CobysCurrencySearcher.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New
---------------------------------------------------------------------------
local base = CobySuite.Config.New({
  savedVariable = "COBYS_CURRENCY_SEARCHER_CONFIG",
  options = {
    MATCH_DESCRIPTIONS = "match_descriptions",
    FOCUS_ON_OPEN      = "focus_on_open",     -- focus the search box when the Currency tab shows
    KEEP_TEXT          = "keep_text",         -- keep the search text while the window is closed
    SEARCH_DELAY       = "search_delay",      -- seconds between the last keystroke and the search
    FLAT_RESULTS       = "flat_results",      -- currencies only, group name after each
    STAR_MODE          = "star_mode",         -- "always" | "results" | "hover"
    STAR_KEEP_FAVORITES = "star_keep_favorites",  -- hover mode: starred currencies keep their star without hovering
    FILTERS_PERSIST    = "filters_persist",   -- keep the filter set across logins
    SAVED_FILTERS      = "saved_filters",     -- { [filterKey] = true }, written only while FILTERS_PERSIST is on
  },
  defaults = {
    ["match_descriptions"] = false,
    ["focus_on_open"]      = false,
    ["keep_text"]          = false,
    ["search_delay"]       = 0.2,
    ["flat_results"]       = false,
    ["star_mode"]          = "always",
    ["star_keep_favorites"] = true,
    ["filters_persist"]    = false,
    ["saved_filters"]      = {},   -- never mutated in place: writers Set a fresh table
  },
  quietKeys = { "saved_filters" },
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
  if COBYS_CURRENCY_SEARCHER_FAVORITES == nil then
    COBYS_CURRENCY_SEARCHER_FAVORITES = {}
  end
end
