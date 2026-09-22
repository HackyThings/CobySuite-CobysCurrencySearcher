-------------------------------------------------------------------------------
-- CobysCurrencySearcher Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow):
-- a sidebar with Search, Favorites and Filters, staged edits that Apply
-- writes through Config.Set, Cancel, and Defaults. Built at load, so opening
-- it never creates frames in combat; the controls are painted from config on
-- every show, and a ConfigChanged event repaints an open window.
-- saved_filters has no control, so Defaults (which stages only the settings
-- the window shows) never touches it.
-------------------------------------------------------------------------------

local Config = CobysCurrencySearcher.Config
local Opt = Config.Options
local U = CobySuite_CobysCurrencySearcher.Utilities
local UI = CobySuite_CobysCurrencySearcher.UI

local WINDOW_W = 600
local WINDOW_H = 360
local SUB_OPTION_INDENT = 24         -- a sub-option sits under its radio's label

local STAR_MODES = {
  { value = "always",  label = "Show the star on every row" },
  { value = "results", label = "Show the star on search results only" },
  { value = "hover",   label = "Show the star only on the row under the mouse" },
}

local window = UI.CreateSettingsWindow({
  name    = "CobysCurrencySearcherOptionsWindow",
  title   = U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " Settings",
  config  = Config,
  width   = WINDOW_W,
  height  = WINDOW_H,
  persist = {
    svTable = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end,
    key = "options",
  },
  watch   = { bus = CobysCurrencySearcher.EventBus, event = CobysCurrencySearcher.Events.ConfigChanged },
  message = function(text) CobysCurrencySearcher.Utilities.Message(text) end,
  categories = {
    {
      key = "search", label = "Search",
      build = function(panel)
        panel:Section("Search")
        panel:Checkbox{
          key = Opt.MATCH_DESCRIPTIONS, label = "Match descriptions too",
          tooltip = "Also match the search text against each currency's description, not only its name.",
        }
        panel:Checkbox{
          key = Opt.FOCUS_ON_OPEN, label = "Focus the search box when the tab opens",
          tooltip = "Start typing the moment the Currency tab shows. Off: click the box first, so movement keys keep working.",
        }
        panel:Checkbox{
          key = Opt.KEEP_TEXT, label = "Keep the search text while the window is closed",
          tooltip = "Closing the character window keeps the search text for this session instead of clearing it.",
        }
        panel:Checkbox{
          key = Opt.FLAT_RESULTS, label = "Flat results",
          tooltip = "Hide the expansion and sub-headers in the results and show only the matching currencies, each with its group dimmed after the name.",
        }
        panel:Slider{
          key = Opt.SEARCH_DELAY, label = "Search delay",
          tooltip = "How long after the last keystroke the results update. 0 searches on every keystroke.",
          min = 0, max = 0.5, step = 0.05,
          format = function(v) return ("%.2f s"):format(v) end,
        }
      end,
    },
    {
      key = "favorites", label = "Favorites",
      build = function(panel)
        panel:Section("Favorites")
        panel:Radio{
          key = Opt.STAR_MODE, options = STAR_MODES,
          tooltip = "Where the favorite star appears.",
        }
        panel:Checkbox{
          key = Opt.STAR_KEEP_FAVORITES, label = "Starred currencies keep their star without hovering",
          tooltip = "With the hover mode, currencies you have starred still show their star all the time.",
          indent = SUB_OPTION_INDENT,
          -- only meaningful with the hover mode
          enabledWhen = function(get) return get(Opt.STAR_MODE) == "hover" end,
        }
      end,
    },
    {
      key = "filters", label = "Filters",
      build = function(panel)
        panel:Section("Filters")
        panel:Checkbox{
          key = Opt.FILTERS_PERSIST, label = "Filters persist between logins",
          tooltip = "Remember which filters are ticked and put them back at your next login. Off: filters last until you log out.",
        }
      end,
    },
  },
})

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  window:Toggle()
end
