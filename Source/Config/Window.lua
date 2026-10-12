-------------------------------------------------------------------------------
-- CobysCurrencySearcher Settings Window
--
-- The suite's standard settings window (CobySuite.UI.CreateSettingsWindow),
-- compact size preset (640 x 460), with the shared styled rows:
-- - Results: the layout as two picture tiles (Grouped / Flat list), what
--   a search matches as a two-choice radio, and the suite's version check
--   (its Updates section)
-- - Favorites: where the stars show as three picture tiles, the hover-only
--   "Always show stars on favorites" under them, how many favorites there
--   are, and Clear all favorites (at once, after a confirmation; outside
--   Apply, Undo Edits and Defaults)
-- - Search box: the cursor on open, what is remembered, the search delay
-- A Guide button beside Defaults, staged edits that Apply writes through
-- Config.Set, Undo Edits and Defaults. Built at load, so opening it never
-- creates frames in combat (the tile previews draw only textures and font
-- strings on frames the kit made at build); the controls are painted from
-- config on every show, a ConfigChanged event repaints an open window, and
-- so does FavoritesChanged (the count and the Clear all button). The addon
-- is also listed under Options > AddOns with a button that opens this
-- window (CobySuite.UI.RegisterSettingsCategory).
-- saved_filters has no control, so Defaults (which stages only the settings
-- the window shows) never touches it.
-------------------------------------------------------------------------------

local Config = CobysCurrencySearcher.Config
local Opt = Config.Options
local U = CobySuite_CobysCurrencySearcher.Utilities
local UI = CobySuite_CobysCurrencySearcher.UI

local SUB_OPTION_INDENT = 24         -- a sub-option sits under the tiles it belongs to

local STAR_ATLAS_ON = "auctionhouse-icon-favorite"
local STAR_ATLAS_OFF = "auctionhouse-icon-favorite-off"
local FUNNEL_ATLAS = "ui-questtrackerbutton-filter"
local MAGNIFIER_ATLAS = "common-search-magnifyingglass"   -- the search box's own glyph
local SPYGLASS_ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local POINTER_ICON = "Interface\\CURSOR\\Point"   -- the game's own pointer

-------------------------------------------------------------------------------
-- Examples in the tiles: the same two sample currencies everywhere, named in
-- the client's language by the game, with English stand-ins when it gives
-- nothing. Drawn with our own textures and font strings, never Blizzard's
-- currency row templates (those are bound to the Currency tab).
-------------------------------------------------------------------------------
local SAMPLES = {
  { id = 1792, name = "Honor" },      -- starred in the star examples
  { id = 1602, name = "Conquest" },
}
local SAMPLE_GROUP = "Player vs. Player"
local SAMPLE_QUERY = "Player"   -- finds both samples through their group
local SAMPLE_ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local ROW_H = 14

local function Sample(i)
  local sample = SAMPLES[i]
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, sample.id)
  if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
    return info.name, info.iconFileID or SAMPLE_ICON
  end
  return sample.name, SAMPLE_ICON
end

-- One example row at line (0 first): opts.star ("on", "off" or nil), the
-- currency's icon and name, opts.tail (gray text after the name) and
-- opts.indent. Returns the row's parts.
local function SampleRow(frame, line, i, opts)
  opts = opts or {}
  local y = -line * ROW_H
  local x = opts.indent or 0
  local parts = {}
  if opts.star then
    parts.Star = frame:CreateTexture(nil, "ARTWORK")
    parts.Star:SetSize(12, 12)
    parts.Star:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 1)
    parts.Star:SetAtlas(opts.star == "on" and STAR_ATLAS_ON or STAR_ATLAS_OFF)
    x = x + 14
  end
  local name, icon = Sample(i)
  parts.Icon = frame:CreateTexture(nil, "ARTWORK")
  parts.Icon:SetSize(12, 12)
  parts.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y - 1)
  parts.Icon:SetTexture(icon)
  parts.Text = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  parts.Text:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 16, y)
  parts.Text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  parts.Text:SetJustifyH("LEFT")
  parts.Text:SetWordWrap(false)
  parts.Text:SetText(opts.tail and (name .. "  " .. U.WrapColor(CobysCurrencySearcher.FLAT_GROUP_COLOR, opts.tail)) or name)
  return parts
end

local function GroupedPreview(frame)
  local header = frame:CreateFontString(nil, "OVERLAY", U.Fonts.SMALL)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  header:SetText(SAMPLE_GROUP)
  SampleRow(frame, 1, 1, { indent = 10 })
  SampleRow(frame, 2, 2, { indent = 10 })
end

local function FlatPreview(frame)
  SampleRow(frame, 0, 1, { tail = SAMPLE_GROUP })
  SampleRow(frame, 1, 2, { tail = SAMPLE_GROUP })
end

-- Every row: both stars, the first one lit
local function EveryRowPreview(frame)
  SampleRow(frame, 0, 1, { star = "on" })
  SampleRow(frame, 1, 2, { star = "off" })
end

-- Search results only: a drawn search box with a query above the same two
-- rows. Tile previews sit on the tile's bottom edge, so these rows line up
-- with the other tiles', whose previews are a line shorter. A picture only,
-- never an edit box inside a clickable tile.
local MOCK_BOX_WIDTH = 64
local function ResultsPreview(frame)
  local box = frame:CreateTexture(nil, "BACKGROUND")
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  box:SetSize(MOCK_BOX_WIDTH, ROW_H - 2)
  local bg = U.Colors.CONTENT_BG
  box:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
  local glass = frame:CreateTexture(nil, "ARTWORK")
  glass:SetSize(10, 10)
  glass:SetPoint("LEFT", box, "LEFT", 3, 0)
  glass:SetAtlas(MAGNIFIER_ATLAS)
  local query = frame:CreateFontString(nil, "OVERLAY", U.Fonts.DATA)
  query:SetPoint("LEFT", glass, "RIGHT", 3, 0)
  query:SetText(SAMPLE_QUERY)
  local gray = U.Colors.LABEL_GRAY
  query:SetTextColor(gray[1], gray[2], gray[3])
  for i = 1, 2 do
    SampleRow(frame, i, i, { star = i == 1 and "on" or "off" })
  end
end

-- On hover: the second row under the pointer with its star; the first
-- (starred) keeps its star only with "Always show stars on favorites",
-- which previewPaint follows as staged. The hovered star is the tile's
-- point, so it is lit (the empty star alone is lost on the selected tile's
-- gold), and the pointer sits at the row's end, clear of the name.
local POINTER_SIZE = 14
local function HoverPreview(frame)
  frame.Starred = SampleRow(frame, 0, 1, { star = "on" })
  local hovered = SampleRow(frame, 1, 2, { star = "off" })
  for _ = 1, 2 do
    local lit = frame:CreateTexture(nil, "OVERLAY")
    lit:SetAllPoints(hovered.Star)
    lit:SetAtlas(STAR_ATLAS_OFF)
    lit:SetBlendMode("ADD")
  end
  local glow = frame:CreateTexture(nil, "BACKGROUND")
  glow:SetPoint("TOPLEFT", hovered.Star, "TOPLEFT", -2, 1)
  glow:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  glow:SetHeight(ROW_H)
  local white = U.Colors.HIGHLIGHT_WHITE
  glow:SetColorTexture(white[1], white[2], white[3], 0.12)
  hovered.Text:SetPoint("RIGHT", frame, "RIGHT", -(POINTER_SIZE + 4), 0)
  local pointer = frame:CreateTexture(nil, "OVERLAY")
  pointer:SetSize(POINTER_SIZE, POINTER_SIZE)
  pointer:SetPoint("TOPRIGHT", hovered.Text, "TOPRIGHT", POINTER_SIZE + 2, -4)
  pointer:SetTexture(POINTER_ICON)
end

local function KeepsFavorites(window)
  return window:Get(Opt.STAR_KEEP_FAVORITES) and true or false
end

-------------------------------------------------------------------------------
-- Favorites: the count and Clear all favorites
-------------------------------------------------------------------------------
local function FavoriteCount()
  local favorites = CobysCurrencySearcher.Favorites   -- loads after this file
  return favorites and favorites.Count() or 0
end

local function CountText()
  local n = FavoriteCount()
  if n == 0 then return "No favorites yet. Click the star at the start of any currency row." end
  return ("You have %d favorite%s, shared by all your characters."):format(n, n == 1 and "" or "s")
end

local clearPopup   -- built under the window

local window = UI.CreateSettingsWindow({
  name    = "CobysCurrencySearcherOptionsWindow",
  title   = U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " Settings",
  icon    = CobysCurrencySearcher.ICON,
  config  = Config,
  size    = "compact",   -- 640 x 460
  persist = {
    svTable = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end,
    key = "options",
  },
  watch   = { bus = CobysCurrencySearcher.EventBus, event = CobysCurrencySearcher.Events.ConfigChanged },
  message = function(text) CobysCurrencySearcher.Utilities.Message(text) end,
  footerButtons = {
    {
      text = "Guide", width = 80,
      tooltip = "Open the feature guide: searching, filters, favorites and clicking a result.",
      onClick = function() if CobysCurrencySearcher.Guide then CobysCurrencySearcher.Guide.Toggle() end end,
    },
  },
  categories = {
    {
      key = "results", label = "Results",
      build = function(panel)
        panel:Section("Layout", { icon = SPYGLASS_ICON, subtitle = "How the matching currencies are listed." })
        panel:Tiles{
          key = Opt.FLAT_RESULTS, columns = 2, height = 124,
          options = {
            {
              value = false, title = "Grouped",
              description = "Matches stay under their headers, like the game's own list.",
              preview = GroupedPreview, previewHeight = 3 * ROW_H,
            },
            {
              value = true, title = "Flat list",
              description = "Only the matching currencies, each with its group in gray after the name.",
              preview = FlatPreview, previewHeight = 3 * ROW_H,
            },
          },
        }
        panel:Section("What a search looks at", {
          icon = "Interface\\Icons\\INV_Misc_Note_01",
          subtitle = "Where the text you type has to appear.",
        })
        panel:Radio{
          key = Opt.MATCH_DESCRIPTIONS,
          options = {
            { value = false, label = "Currency and group names",
              description = "A group name finds its currencies. Active filters still apply." },
            { value = true, label = "Also search descriptions",
              description = "Also finds a currency by what its description says." },
          },
        }
        CobySuite_CobysCurrencySearcher.VersionCheck.AddSettingsRows(panel, Opt.VERSION_CHECK)
      end,
    },
    {
      key = "favorites", label = "Favorites",
      build = function(panel)
        panel:Section("Stars", {
          atlas = STAR_ATLAS_ON,
          subtitle = "Click the star at the start of a currency row to make it a favorite.",
        })
        -- kept on the panel for the Search suite's hover check and the Verify scenes
        panel.StarTiles = panel:Tiles{
          key = Opt.STAR_MODE, columns = 3, height = 124,
          options = {
            {
              value = "always", title = "Every row",
              description = "In the game's list and in search results.",
              preview = EveryRowPreview, previewHeight = 2 * ROW_H,
            },
            {
              value = "results", title = "Search results",
              description = "Stars appear when searching or filtering.",
              preview = ResultsPreview, previewHeight = 3 * ROW_H,
            },
            {
              value = "hover", title = "On hover",
              description = function(w)
                return KeepsFavorites(w) and "Other stars show under the mouse; favorites keep theirs."
                  or "Stars show only on the row under the mouse."
              end,
              preview = HoverPreview, previewHeight = 2 * ROW_H,
              previewPaint = function(frame, _, w)
                if frame.Starred then frame.Starred.Star:SetShown(KeepsFavorites(w)) end
              end,
            },
          },
        }
        panel:Checkbox{
          key = Opt.STAR_KEEP_FAVORITES, label = "Always show stars on favorites",
          description = "Your favorites keep a lit star without hovering.",
          indent = SUB_OPTION_INDENT,
          -- only meaningful with the hover mode; its value is kept while hidden
          visibleWhen = function(get) return get(Opt.STAR_MODE) == "hover" end,
        }
        panel:Section("Your favorites", { icon = CobysCurrencySearcher.ICON })
        panel:Note{ atlas = STAR_ATLAS_ON, text = CountText }
        panel:Note{
          atlas = FUNNEL_ATLAS,
          text = "Tick Favorites in the funnel menu beside the search box to see only your favorites.",
        }
        panel:Button{
          text = "Clear All Favorites...", width = 180,
          description = "Clears favorites for all your characters after confirmation.",
          immediate = true,
          enabledWhen = function() return FavoriteCount() > 0 end,
          onClick = function()
            local n = FavoriteCount()
            if n == 0 then return end
            clearPopup:SetBody(("Clear your %d favorite%s for all your characters?\n\nThis does not wait for Apply and cannot be undone.")
              :format(n, n == 1 and "" or "s"))
            clearPopup:Show()
          end,
        }
      end,
    },
    {
      key = "searchbox", label = "Search box",
      build = function(panel)
        panel:Section("When the Currency tab opens", { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01" })
        panel:Checkbox{
          key = Opt.FOCUS_ON_OPEN, label = "Put the cursor in the search box",
          description = "Movement keys type into the box until you press Enter or click elsewhere.",
        }
        panel:Section("Remember", {
          icon = "Interface\\Icons\\INV_Misc_Book_09",
          subtitle = "What stays when you close the window or log out.",
        })
        panel:Checkbox{
          key = Opt.KEEP_TEXT, label = "Remember my search while the window is closed",
          description = "Your search is still there when you reopen the Currency tab. Logging out or reloading clears it.",
        }
        panel:Checkbox{
          key = Opt.FILTERS_PERSIST, label = "Remember filters between logins",
          description = "The filters you tick in the funnel menu come back at your next login.",
        }
        panel:Section("Fine tuning", { icon = "Interface\\Icons\\INV_Misc_Gear_01" })
        panel:Slider{
          key = Opt.SEARCH_DELAY, label = "Search delay",
          description = "How long after your last keystroke the results update.",
          min = 0, max = 0.5, step = 0.05,
          minLabel = "Instant", maxLabel = "0.50 s",
          format = function(v)
            if v < 0.001 then return "Instant" end
            return ("%.2f s"):format(v)
          end,
        }
      end,
    },
  },
})

-- Clear all favorites asks first, in an addon-owned dialog (never
-- StaticPopupDialogs); it acts at once, outside Apply, Undo Edits and Defaults
clearPopup = UI.CreateDialogPopup({
  name = "CobysCurrencySearcherClearFavoritesPopup",
  icon = CobysCurrencySearcher.ICON,
  title = "Clear all favorites?",
  danger = true,
  width = 380,   -- the height follows the body
  parent = window,
  point = { "CENTER", window, "CENTER", 0, 0 },
  confirmText = "Clear Favorites",
  hidden = true,
  onConfirm = function()
    local favorites = CobysCurrencySearcher.Favorites
    if favorites then favorites.ClearAll() end
  end,
})
window:HookScript("OnHide", function() clearPopup:Hide() end)

-- A star clicked or cleared while the window is open repaints the count and
-- the Clear all button (Refresh does nothing while it's hidden)
CobysCurrencySearcher.EventBus:Register({
  ReceiveEvent = function() window:Refresh() end,
}, { CobysCurrencySearcher.Events.FavoritesChanged })

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
function Config.ToggleSettings()
  window:Toggle()
end

function Config.OpenSettings()
  window:Open()
end

-------------------------------------------------------------------------------
-- Options > AddOns entry (registered once this addon has finished loading)
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded("CobysCurrencySearcher", function()
  UI.RegisterSettingsCategory({
    name        = "Coby's Currency Searcher",
    brandColor  = CobysCurrencySearcher.BRAND_COLOR,
    version     = CobysCurrencySearcher.VERSION,
    description = {
      "Adds a search box to the Currency tab. Finds currencies inside collapsed headers and filters the list without gaps.",
      "The settings live in the addon's own settings window.",
    },
    slash       = "/ccs settings",
    onOpen      = Config.OpenSettings,
  })
end)
