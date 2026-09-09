-------------------------------------------------------------------------------
-- CobysCurrencySearcher Settings Window
--
-- The shell comes from CobySuite.UI.CreateWindow (solid background, drag,
-- saved position, Escape through UISpecialFrames, combat-safe close). The
-- form is built with CobySuite.UI.CreateFormLayout. Changes apply the
-- moment a control changes (no Stage/Apply), written through Config.Set.
-------------------------------------------------------------------------------

local Config = CobysCurrencySearcher.Config
local U = CobySuite.Utilities
local UI = CobySuite.UI

local WINDOW_W  = 400
local WINDOW_H  = 428   -- three sections, no slack below
local PANEL_PAD = 16
local FORM_START_Y = -1              -- first header 15px higher than the builder default
local SECTION_GAP = 4                -- between a section's last row and the next header
local SECTION_DIVIDER_OFFSET = -7    -- divider 3px further below the section title than the default
local SUB_OPTION_INDENT = 24         -- a sub-option sits under its radio's label

local STAR_MODES = {
  { value = "always",  label = "Show the star on every row" },
  { value = "results", label = "Show the star on search results only" },
  { value = "hover",   label = "Show the star only on the row under the mouse" },
}

local frame
local widgets = {}

local function RefreshStarModes()
  local mode = Config.Get(Config.Options.STAR_MODE)
  widgets.starMode:SetValue(mode)
  widgets.keepFavorites:SetChecked(Config.Get(Config.Options.STAR_KEEP_FAVORITES))
  widgets.keepFavorites:SetEnabled(mode == "hover")   -- only meaningful with the hover mode
end

local function Refresh()
  widgets.matchDescriptions:SetChecked(Config.Get(Config.Options.MATCH_DESCRIPTIONS))
  widgets.focusOnOpen:SetChecked(Config.Get(Config.Options.FOCUS_ON_OPEN))
  widgets.keepText:SetChecked(Config.Get(Config.Options.KEEP_TEXT))
  widgets.flatResults:SetChecked(Config.Get(Config.Options.FLAT_RESULTS))
  widgets.searchDelay:SetValue(Config.Get(Config.Options.SEARCH_DELAY))
  widgets.filtersPersist:SetChecked(Config.Get(Config.Options.FILTERS_PERSIST))
  RefreshStarModes()
end

-------------------------------------------------------------------------------
-- Frame construction
-------------------------------------------------------------------------------
local function BuildFrame()
  if frame then return frame end

  local f = UI.CreateWindow({
    name = "CobysCurrencySearcherOptionsWindow",
    title = U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " Settings",
    width = WINDOW_W,
    height = WINDOW_H,
    escapeCloses = true,
    persist = {
      svTable = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end,
      key = "options",
      defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
      fixedSize = true,   -- fixed layout: ignore any saved size
    },
  })
  f:SetScript("OnShow", Refresh)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 8, -28)
  content:SetSize(WINDOW_W - 16, WINDOW_H - 28 - 8)

  -- Label x, row height are the builder defaults.
  local form = UI.CreateFormLayout(content, {
    width          = WINDOW_W - 16,
    dividerPadding = PANEL_PAD,
    startY         = FORM_START_Y,
  })

  form:Section("Search", { dividerOffset = SECTION_DIVIDER_OFFSET })

  widgets.matchDescriptions = form:Checkbox{
    label        = "Match descriptions too",
    tooltip      = "Also match the search text against each currency's description, not only its name.",
    optionKey    = "MATCH_DESCRIPTIONS",
    initialValue = Config.Get(Config.Options.MATCH_DESCRIPTIONS),
    onChange     = function(v) Config.Set(Config.Options.MATCH_DESCRIPTIONS, v) end,
  }

  widgets.focusOnOpen = form:Checkbox{
    label        = "Focus the search box when the tab opens",
    tooltip      = "Start typing the moment the Currency tab shows. Off: click the box first, so movement keys keep working.",
    optionKey    = "FOCUS_ON_OPEN",
    initialValue = Config.Get(Config.Options.FOCUS_ON_OPEN),
    onChange     = function(v) Config.Set(Config.Options.FOCUS_ON_OPEN, v) end,
  }

  widgets.keepText = form:Checkbox{
    label        = "Keep the search text while the window is closed",
    tooltip      = "Closing the character window keeps the search text for this session instead of clearing it.",
    optionKey    = "KEEP_TEXT",
    initialValue = Config.Get(Config.Options.KEEP_TEXT),
    onChange     = function(v) Config.Set(Config.Options.KEEP_TEXT, v) end,
  }

  widgets.flatResults = form:Checkbox{
    label        = "Flat results",
    tooltip      = "Hide the expansion and sub-headers in the results and show only the matching currencies, each with its group dimmed after the name.",
    optionKey    = "FLAT_RESULTS",
    initialValue = Config.Get(Config.Options.FLAT_RESULTS),
    onChange     = function(v) Config.Set(Config.Options.FLAT_RESULTS, v) end,
  }

  widgets.searchDelay = form:Slider{
    label        = "Search delay",
    tooltip      = "How long after the last keystroke the results update. 0 searches on every keystroke.",
    min          = 0,
    max          = 0.5,
    step         = 0.05,
    initialValue = Config.Get(Config.Options.SEARCH_DELAY),
    format       = function(v) return ("%.2f s"):format(v) end,
    optionKey    = "SEARCH_DELAY",
    onChange     = function(v) Config.Set(Config.Options.SEARCH_DELAY, v) end,
  }

  form:Section("Favorites", { gap = SECTION_GAP, dividerOffset = SECTION_DIVIDER_OFFSET })

  widgets.starMode = form:RadioGroup{
    options      = STAR_MODES,
    tooltip      = "Where the favorite star appears.",
    initialValue = Config.Get(Config.Options.STAR_MODE),
    onChange     = function(value)
      Config.Set(Config.Options.STAR_MODE, value)
      RefreshStarModes()
    end,
  }

  widgets.keepFavorites = form:Checkbox{
    label        = "Starred currencies keep their star without hovering",
    tooltip      = "With the hover mode, currencies you have starred still show their star all the time.",
    optionKey    = "STAR_KEEP_FAVORITES",
    indent       = SUB_OPTION_INDENT,
    initialValue = Config.Get(Config.Options.STAR_KEEP_FAVORITES),
    onChange     = function(v) Config.Set(Config.Options.STAR_KEEP_FAVORITES, v) end,
  }

  form:Section("Filters", { gap = SECTION_GAP, dividerOffset = SECTION_DIVIDER_OFFSET })

  widgets.filtersPersist = form:Checkbox{
    label        = "Filters persist between logins",
    tooltip      = "Remember which filters are ticked and put them back at your next login. Off: filters last until you log out.",
    optionKey    = "FILTERS_PERSIST",
    initialValue = Config.Get(Config.Options.FILTERS_PERSIST),
    onChange     = function(v) Config.Set(Config.Options.FILTERS_PERSIST, v) end,
  }

  frame = f
  return f
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  if not frame and InCombatLockdown() then
    -- Root rule: no CreateFrame in combat. The window is built lazily, so
    -- refuse the first open until combat ends rather than deferring it.
    CobysCurrencySearcher.Utilities.Message("The settings window opens after combat.")
    return
  end
  BuildFrame():Toggle()
end
