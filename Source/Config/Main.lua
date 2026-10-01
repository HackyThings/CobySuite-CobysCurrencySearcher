local Config = CobysCurrencySearcher.Config

---------------------------------------------------------------------------
-- Shared config base via CobySuite.Config.New
---------------------------------------------------------------------------
local base = CobySuite_CobysCurrencySearcher.Config.New({
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
    SAVED_FILTERS      = "saved_filters",     -- { [filterKey] = true }, non-empty only while FILTERS_PERSIST is on (emptied when it turns off)
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
  -- Set refuses a failing value and InitializeData puts the default back for
  -- a failing saved one (a hand-edited or damaged file). The ranges are what
  -- the settings window offers, in 1.0.1 too, so an upgrade resets nothing.
  -- saved_filters is a table and has no rule; InitializeData checks it.
  validate = {
    ["match_descriptions"]  = { type = "boolean" },
    ["focus_on_open"]       = { type = "boolean" },
    ["keep_text"]           = { type = "boolean" },
    ["search_delay"]        = { type = "number", min = 0, max = 0.5 },
    ["flat_results"]        = { type = "boolean" },
    ["star_mode"]           = { type = "string", values = { "always", "results", "hover" } },
    ["star_keep_favorites"] = { type = "boolean" },
    ["filters_persist"]     = { type = "boolean" },
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
Config.CheckValue    = base.CheckValue
Config.Get           = base.Get
Config.Set           = base.Set
Config.Reset         = base.Reset

---------------------------------------------------------------------------
-- InitializeData: wraps base with addon-specific SavedVariable init
---------------------------------------------------------------------------
function Config.InitializeData()
  base.InitializeData()

  -- Anything but a table here is a damaged file: start that table over
  if type(COBYS_CURRENCY_SEARCHER_WINDOW_STATE) ~= "table" then
    COBYS_CURRENCY_SEARCHER_WINDOW_STATE = {}
  end
  if type(COBYS_CURRENCY_SEARCHER_FAVORITES) ~= "table" then
    COBYS_CURRENCY_SEARCHER_FAVORITES = {}
  end
  if type(COBYS_CURRENCY_SEARCHER_CONFIG.saved_filters) ~= "table" then
    COBYS_CURRENCY_SEARCHER_CONFIG.saved_filters = {}
  end
end
