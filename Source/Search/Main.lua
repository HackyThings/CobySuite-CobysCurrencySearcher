-------------------------------------------------------------------------------
-- CobysCurrencySearcher Search
--
-- Adds a live search box to Blizzard's Currency tab (TokenFrame) and shows
-- the matches in a results list of our own that sits exactly over Blizzard's
-- list. How it works, and why it is built this way:
--
--   * Warband currency transfer is a protected server call. WoW only allows
--     it from an execution path that never touched addon-written data, and
--     the row the user clicks is what carries the currency id all the way to
--     the transfer menu's confirm button. Any list an addon builds, rebuilds
--     (TokenFrame:Update() from addon code), scrolls, or writes into produces
--     tainted rows, and a transfer started from one of them fails with
--     ADDON_ACTION_FORBIDDEN. Only Blizzard's own rebuild of its own list,
--     from a user action such as opening the tab or clicking a header, gives
--     clean rows. So Blizzard's list is never touched: no data-provider swap,
--     no Update() calls, no scrolling, no writes to TokenFrame fields.
--   * While a search is active, Blizzard's ScrollBox and ScrollBar are faded
--     to alpha 0 (a C-side property, no scripts run) and our results ScrollBox
--     and ScrollBar are shown in the same place, built from the same Blizzard
--     templates (TokenHeaderTemplate, TokenSubHeaderTemplate,
--     TokenEntryTemplate), the same view padding, spacing and indents, so
--     the two lists are indistinguishable.
--   * GetCurrencyListInfo only enumerates rows that are currently visible;
--     children of a collapsed header do not exist in the index space. Each
--     refresh therefore expands every collapsed header, reads the whole list
--     into our own row tables, and collapses those headers again, all in one
--     synchronous pass, so Blizzard's hidden list always matches the game's
--     collapse state. Nothing about the user's headers changes.
--   * Expanding a header inserts rows after it and collapsing removes them,
--     so the expand walk runs forward (re-reading the size each step) and the
--     collapse pass runs backward over the recorded indices.
--   * Headers have no currencyID. They are keyed by their path ("Parent/Sub")
--     so same-named sub-headers under different parents stay distinct.
--   * A header whose own name matches keeps its whole group. Otherwise a
--     header is kept only when at least one descendant matches. Collapsing a
--     header inside the results only hides its rows in the results.
--   * The filter icon (funnel) beside the box opens a small menu of
--     checkbox filters (Transferable: currencies that can move between the
--     characters of a Warband). A filter narrows the results with or
--     without search text; headers then stay only for the rows they still
--     contain. Filters last for the session and, like the text, are
--     cleared by a result click.
--   * Every currency row, in Blizzard's list and in the results, carries a
--     star at its right edge (filled for favorites, empty for the rest)
--     that marks the currency as a favorite, saved account-wide. The
--     Favorites filter shows only starred currencies, in their usual order.
--     The star is a child button attached by a hooksecurefunc post-hook on
--     TokenEntryMixin:Initialize, kept in our own table; a Blizzard row is
--     only read, never written to (see "Favorite star").
--   * Clicking a result opens our own options popup (a replica of
--     TokenFramePopup) and the results stay. Unused and Show on Backpack
--     work from it directly (unprotected calls). Its Transfer button is the
--     one action that has to reach Blizzard's own UI: it stashes the
--     search, runs a secure macro that flips the character window away and
--     back (a clean rebuild), /clicks the target's row through a delegate
--     and then /clicks Blizzard's transfer toggle through a second delegate,
--     so Blizzard's popup and the transfer menu open for that currency; see
--     "Secure transfer hand-off" below. The search and filters come straight
--     back in the same click, with the transfer menu open beside the window.
--
-- Blizzard only rebuilds its list from Update(); nothing on the frame listens
-- to CURRENCY_DISPLAY_UPDATE. We post-hook Update() only to refresh our own
-- results when their data changes, never to touch theirs. While the overlay
-- is up, quantity changes (CURRENCY_DISPLAY_UPDATE with a currencyType)
-- refresh our results too.
-------------------------------------------------------------------------------

local Debug = CobysCurrencySearcher.Debug
local Config = CobysCurrencySearcher.Config
local Utilities = CobysCurrencySearcher.Utilities
local Favorites = CobysCurrencySearcher.Favorites
local U = CobySuite.Utilities
local UI = CobySuite.UI

local Search = {}
CobysCurrencySearcher.Search = Search

local DEBOUNCE_SECONDS = 0.2
local BOX_WIDTH = 117     -- from just right of the portrait to the filter icon
local BOX_GAP = 5         -- search box to the funnel
local ICON_GAP = 3        -- funnel to the settings gear
local DROPDOWN_GAP = 6    -- settings gear to Blizzard's dropdown
local MAX_LETTERS = 50

-- The funnel and its menu come from CobySuite.UI.CreateFilterButton (the
-- objective tracker's 18x19 funnel, MenuStyle1 menu). The settings gear
-- beside it is CobySuite.UI.CreateFilterStyleButton: the funnel's own badge
-- with the raid manager's settings glyph (GM-icon-settings,
-- Blizzard_CompactRaidFrameManager.xml) drawn over it in the funnel's gold.
local SETTINGS_GLYPH_ATLAS = "GM-icon-settings"
local SETTINGS_GLYPH_INSET = -1   -- the glyph atlas is padded for a 40px button

-- Favorite stars (CobySuite.UI.CreateFavoriteStar, the auction house star)
-- sit at the left edge of every row. Blizzard's account-wide / transferable
-- icon, which shows in that slot on hover and selection, moves right of the
-- star and the name follows it as in Blizzard's template. The backpack
-- check keeps its own slot right of the currency icon.
local STAR_HEIGHT = 16
local STAR_LEFT_X = 4             -- star at the row's left edge
local ACCOUNT_ICON_GAP = 0        -- between the star and the account-wide icon's frame
local FLAT_GROUP_COLOR = "808080" -- the group name after a flat result's name
local EMPTY_LABEL_WIDTH = 240

-- Each filter keeps a currency row only when test(row) is true. Headers then
-- stay only for the rows they still contain.
local FILTER_DEFS = {
  {
    key = "favorites",
    label = "Favorites",
    tooltip = "Only the currencies you starred. Click the star at the start of any currency row.",
    test = function(data) return Favorites ~= nil and Favorites.IsFavorite(data.currencyID) end,
  },
  {
    key = "transferable",
    label = "Transferable",
    tooltip = "Only currencies that can be transferred between the characters of your Warband.",
    test = function(data) return data.isAccountTransferable == true end,
  },
  {
    key = "owned",
    label = "Owned",
    tooltip = "Only currencies with a balance above zero.",
    test = function(data) return (data.quantity or 0) > 0 end,
  },
  {
    key = "capped",
    label = "Capped",
    tooltip = "Only currencies at their maximum, or at this week's cap.",
    test = function(data)
      local max = data.maxQuantity or 0
      if max > 0 then
        local held = data.useTotalEarnedForMaxQty and (data.totalEarned or 0) or (data.quantity or 0)
        if held >= max then return true end
      end
      local weeklyMax = data.maxWeeklyQuantity or 0
      return data.canEarnPerWeek == true and weeklyMax > 0 and (data.quantityEarnedThisWeek or 0) >= weeklyMax
    end,
  },
  {
    key = "weekly",
    label = "Weekly",
    tooltip = "Only currencies with a weekly earning limit.",
    test = function(data) return data.canEarnPerWeek == true end,
  },
  {
    key = "backpack",
    label = "On Backpack",
    tooltip = "Only currencies shown on the backpack bar.",
    test = function(data) return data.isShowInBackpack == true end,
  },
}

-- Blizzard's list geometry (TokenFrameMixin:OnLoad), mirrored exactly.
local LIST_PADDING = 10
local LIST_SPACING = 2

-- Blizzard's popup geometry (TokenFramePopup in Blizzard_TokenUI.xml).
local POPUP_WIDTH = 197
local POPUP_HEIGHT_DEFAULT = 100
local POPUP_HEIGHT_TRANSFER_ONLY = 90
local POPUP_HEIGHT_FULL = 135

-- Macro run on a secure path by the popup's Transfer button (see "Secure
-- transfer hand-off"). Under the 255-character limit of 11.0.2 by a wide
-- margin.
local TRANSFER_MACRO = "/click CharacterFrameTab1\n/click CharacterFrameTab3\n/click CobysCurrencySearcherClickStep\n/click CobysCurrencySearcherTransferStep"

local searchBox
local emptyLabel
local query = ""           -- normalized active query; "" when no search text is active
local filters = {}         -- filter key -> true while that filter is on (see FILTER_DEFS)
local stars = setmetatable({}, { __mode = "k" })  -- row frame -> its star button; Blizzard's rows and ours
local watchedOverrides = {}  -- currencyID -> watched, set by our popup until Blizzard's next rebuild (see SetWatched)
local resultRows = setmetatable({}, { __mode = "k" })  -- row frame -> true for rows of our results list
local hoveredRow           -- row under the mouse, for the hover-only star mode
local filterButton         -- our filter icon button, right of the search box
local settingsButton       -- our settings gear, between the filter icon and Blizzard's dropdown
local overlayActive = false  -- the results overlay is up: search text or a filter is active
local RefreshFilterUI      -- defined under "Filter button and menu"

local overlay              -- container covering Blizzard's ScrollBox + ScrollBar
local resultsBox           -- our WowScrollBoxList
local resultsBar           -- our MinimalScrollBar
local collapsedInResults = {}  -- header path key -> true, collapsed inside the results only
local lastResults          -- array of row tables currently shown

local popup                -- our replica of TokenFramePopup
local selectedCurrencyID   -- currency whose options popup is open (nil = none)
local blizzardListStale = false  -- our popup reordered the underlying list; see SetUnused

local clickStep            -- CobysCurrencySearcherClickStep, the /click delegate for the row; created once
local transferStep         -- CobysCurrencySearcherTransferStep, the /click delegate for Blizzard's transfer toggle; created once
local macroInFlight = false  -- true from the Transfer button's PreClick to its PostClick
local macroTarget          -- { currencyID, name, path, ancestors } for the hand-off in flight
local stashedSearch        -- { text, filters } to bring back once the transfer menu is open
local refreshQuantities    -- Coalesce handle for CURRENCY_DISPLAY_UPDATE refreshes (see OnCurrencyDisplayUpdate)
local lastCollapsedKeys    -- header path keys that were collapsed at the last snapshot
local restoreCollapsedKeys -- collapse state to put back on tab hide (nil = nothing to restore)

-------------------------------------------------------------------------------
-- Header path keys
--
-- `stack` is an array indexed by depth + 1 holding the header names above the
-- row being visited. Call in list order so the ancestry is always current.
-------------------------------------------------------------------------------
local function HeaderKey(stack, info)
  local depth = info.currencyListDepth or 0
  for d = #stack, depth + 1, -1 do
    stack[d] = nil
  end
  for d = 1, depth do
    if stack[d] == nil then stack[d] = "" end   -- orphan sub-header; keep concat safe
  end
  stack[depth + 1] = info.name or ""
  return table.concat(stack, "/", 1, depth + 1)
end

-------------------------------------------------------------------------------
-- Snapshot of the currency list
--
-- Expands every collapsed header, copies every row, then collapses those
-- headers again. Synchronous, so Blizzard's hidden list never sees a state
-- that differs from the game's.
-------------------------------------------------------------------------------
-- Returns { indices = {...}, keys = { [path] = true } } for the headers it
-- expanded. Indices are positions in the fully expanded list; keys let a
-- caller find the same headers again after the list has been reordered.
local function ExpandAllHeaders()
  local expanded = { indices = {}, keys = {} }
  local stack = {}
  local i = 1
  -- Re-read the size every iteration: expanding inserts the header's
  -- children right after it, and the loop then visits those rows too, so
  -- nested collapsed sub-headers are handled by the same pass.
  while i <= C_CurrencyInfo.GetCurrencyListSize() do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info and info.isHeader then
      local key = HeaderKey(stack, info)
      if not info.isHeaderExpanded then
        C_CurrencyInfo.ExpandCurrencyList(i, true)
        expanded.indices[#expanded.indices + 1] = i
        expanded.keys[key] = true
      end
    end
    i = i + 1
  end
  return expanded
end

-- Collapse in descending index order so a collapse never shifts an index
-- still ahead of it. Only valid while the list is exactly as the expand
-- walk left it (nothing added, removed or moved in between).
local function CollapseAgain(expanded)
  local indices = expanded.indices
  for n = #indices, 1, -1 do
    C_CurrencyInfo.ExpandCurrencyList(indices[n], false)
  end
end

-- Same result as CollapseAgain, but finds the headers by path key in a
-- forward walk first, so it survives a list that was reordered after the
-- expand walk (marking a currency unused moves it between groups).
local function CollapseByKey(expanded)
  local targets = {}
  local stack = {}
  for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info and info.isHeader then
      local key = HeaderKey(stack, info)
      if info.isHeaderExpanded and expanded.keys[key] then
        targets[#targets + 1] = i
      end
    end
  end
  for n = #targets, 1, -1 do
    C_CurrencyInfo.ExpandCurrencyList(targets[n], false)
  end
end

local function CopyRow(info, index, stack)
  local row = {}
  for k, v in pairs(info) do
    row[k] = v
  end
  row.currencyIndex = index          -- index in the fully expanded list; display only
  if info.isHeader then
    row.path = HeaderKey(stack, info)
    -- Everything is expanded in the snapshot; the results decide visibility.
    row.isHeaderExpanded = not collapsedInResults[row.path]
  else
    -- Ancestors only: a currency at depth d sits under the headers at
    -- depths 0 .. d-1, not under a sub-header block listed before it.
    local depth = info.currencyListDepth or 0
    local n = math.min(#stack, depth)
    row.path = table.concat(stack, " > ", 1, n)
    row.ancestors = {}
    for d = 1, n do
      row.ancestors[table.concat(stack, "/", 1, d)] = true
    end
  end
  return row
end

local function SnapshotCurrencyList()
  local expanded = ExpandAllHeaders()
  lastCollapsedKeys = expanded.keys
  local rows = {}
  local stack = {}
  for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info then
      rows[#rows + 1] = CopyRow(info, i, stack)
    end
  end
  CollapseAgain(expanded)
  return rows, #expanded.indices
end

-- Runs `fn(index)` with the list fully expanded, for the row whose currencyID
-- matches. Used for the one action that only exists by list index (Unused).
-- `fn` may reorder the list, so the headers are collapsed again by key.
local function WithExpandedIndex(currencyID, fn)
  local expanded = ExpandAllHeaders()
  local found = false
  for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info and not info.isHeader and info.currencyID == currencyID then
      fn(i)
      found = true
      break
    end
  end
  CollapseByKey(expanded)
  return found
end

-- Folds every header except the target's ancestors so Blizzard's next
-- rebuild puts the target within the first screen of rows.
local function CollapseAllExcept(ancestorKeys)
  ExpandAllHeaders()
  local targets = {}
  local stack = {}
  for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info and info.isHeader then
      local key = HeaderKey(stack, info)
      if not ancestorKeys[key] then
        targets[#targets + 1] = i
      end
    end
  end
  for n = #targets, 1, -1 do
    C_CurrencyInfo.ExpandCurrencyList(targets[n], false)
  end
end

-- Puts the user's collapse state back: everything expanded except the keys
-- recorded before the first result click.
local function RestoreCollapseState()
  if not restoreCollapsedKeys then return end
  local keys = restoreCollapsedKeys
  restoreCollapsedKeys = nil
  ExpandAllHeaders()
  CollapseByKey({ keys = keys })
  Debug.State("SEARCH", "Restored the header collapse state from before the result click")
end

-------------------------------------------------------------------------------
-- Matching
-------------------------------------------------------------------------------
-- The list API (GetCurrencyListInfo) leaves description empty; the
-- per-currency API has it. Looked up once per currency and kept for the
-- session, and only while the option is on.
local descriptions = {}   -- currencyID -> lowercased description ("" when none)

local function DescriptionOf(data)
  local id = data.currencyID
  if not id then return "" end
  local desc = descriptions[id]
  if desc == nil then
    desc = data.description
    if not desc or desc == "" then
      local info = C_CurrencyInfo.GetCurrencyInfo(id)
      desc = info and info.description or ""
    end
    desc = strlower(desc)
    descriptions[id] = desc
  end
  return desc
end

local function Matches(data, needle, matchDescriptions)
  local name = data.name
  if name and strfind(strlower(name), needle, 1, true) then
    return true
  end
  if matchDescriptions and not data.isHeader then
    local desc = DescriptionOf(data)
    if desc ~= "" and strfind(desc, needle, 1, true) then
      return true
    end
  end
  return false
end

local function AnyFilterActive()
  return next(filters) ~= nil
end

local function PassesFilters(data)
  for _, def in ipairs(FILTER_DEFS) do
    if filters[def.key] and not def.test(data) then
      return false
    end
  end
  return true
end

-- A search is active, and the results overlay belongs up, whenever there is
-- search text or a filter is on.
local function IsSearchActive()
  return query ~= "" or AnyFilterActive()
end

-- "'text' [Transferable]", for the log.
local function SearchDescription()
  local labels = {}
  for _, def in ipairs(FILTER_DEFS) do
    if filters[def.key] then
      labels[#labels + 1] = def.label
    end
  end
  local text = "'" .. query .. "'"
  if #labels > 0 then
    text = text .. " [" .. table.concat(labels, ", ") .. "]"
  end
  return text
end

local function MarkStackKept(stack, keep)
  for i = 1, #stack do
    keep[stack[i].data] = true
  end
end

-- Returns the subset of `rows` that matches `needle` and passes the active
-- filters, in list order, plus the number of currency rows (non-headers)
-- kept. Rows under a header the user collapsed inside the results are left
-- out. An empty needle matches every name, so a filter alone lists the
-- whole filtered tab.
local function BuildResults(rows, needle, matchDescriptions)
  local keep = {}
  local stack = {}   -- ancestry of the row being visited: { data, depth, force }
  local kept = 0
  local filtered = AnyFilterActive()

  for _, data in ipairs(rows) do
    local depth = data.currencyListDepth or 0
    -- A row at depth d belongs to the nearest header at depth d-1. Pop any
    -- header block at the same or deeper depth that precedes it, otherwise
    -- a sibling currency listed after a sub-header's children is attributed
    -- to that sub-header.
    while #stack > 0 and stack[#stack].depth >= depth do
      stack[#stack] = nil
    end
    if data.isHeader then
      local force = (#stack > 0 and stack[#stack].force) or Matches(data, needle, matchDescriptions)
      stack[#stack + 1] = { data = data, depth = depth, force = force }
      -- A matching header keeps its whole group, unless a filter is on: then
      -- it stays only for the rows that pass, like any other header.
      if force and not filtered then
        MarkStackKept(stack, keep)
      end
    else
      local force = #stack > 0 and stack[#stack].force
      if (force or Matches(data, needle, matchDescriptions)) and PassesFilters(data) then
        keep[data] = true
        kept = kept + 1
        MarkStackKept(stack, keep)
      end
    end
  end

  local results = {}
  local flat = Config.Get(Config.Options.FLAT_RESULTS)   -- currencies only, no headers
  local hiddenBelow   -- depth of the nearest results-collapsed header, or nil
  for _, data in ipairs(rows) do
    local depth = data.currencyListDepth or 0
    if hiddenBelow and depth <= hiddenBelow then
      hiddenBelow = nil
    end
    if keep[data] and not hiddenBelow and not (flat and data.isHeader) then
      results[#results + 1] = data
      if data.isHeader and collapsedInResults[data.path] and not flat then
        hiddenBelow = depth
      end
    end
  end
  return results, kept
end

-------------------------------------------------------------------------------
-- Results list
-------------------------------------------------------------------------------
local function IsCurrencyDataReady()
  if C_CurrencyInfo.DoesCurrentFilterRequireAccountCurrencyData() then
    return C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
  end
  return true
end

local function SetEmptyLabelShown(shown, text)
  if emptyLabel then
    if text then
      emptyLabel:SetText(text)
    end
    emptyLabel:SetShown(shown)
  end
end

local RefreshPopup   -- forward declaration

local function FindResult(currencyID)
  if not lastResults then return nil end
  for _, data in ipairs(lastResults) do
    if not data.isHeader and data.currencyID == currencyID then
      return data
    end
  end
  return nil
end

-- Rebuilds the results from a fresh snapshot. Safe to call at any time while
-- a search is active; it never touches Blizzard's list.
local function Refresh()
  if not IsSearchActive() or not resultsBox then return end

  if not IsCurrencyDataReady() then
    -- Blizzard is showing its loading spinner; show nothing until the data
    -- arrives (their Update fires again then, and our hook refreshes).
    resultsBox:SetDataProvider(CreateDataProvider(), ScrollBoxConstants.RetainScrollPosition)
    lastResults = nil
    SetEmptyLabelShown(false)
    return
  end

  local rows, expanded = SnapshotCurrencyList()
  local results, kept = BuildResults(rows, query, Config.Get(Config.Options.MATCH_DESCRIPTIONS))
  lastResults = results
  resultsBox:SetDataProvider(CreateDataProvider(results), ScrollBoxConstants.RetainScrollPosition)
  if kept == 0 and filters.favorites and Favorites.Count() == 0 then
    SetEmptyLabelShown(true, "No favorites yet. Click the star at the start of any currency row.")
  else
    SetEmptyLabelShown(kept == 0, "No matching currencies")
  end

  if popup and popup:IsShown() then
    local data = FindResult(selectedCurrencyID)
    if data then
      RefreshPopup(data)
    else
      popup:Hide()
    end
  end

  Debug.Log("SEARCH", "%s: %d currencies, %d of %d rows shown (%d header(s) expanded for the snapshot)",
    SearchDescription(), kept, #results, #rows, expanded)
end

-------------------------------------------------------------------------------
-- Row behaviour (mirrors TokenEntryMixin / TokenHeaderMixin without ever
-- touching TokenFrame)
-------------------------------------------------------------------------------
local function EntryIsSelected(self)
  return popup ~= nil and popup:IsShown()
    and self.elementData ~= nil and self.elementData.currencyID == selectedCurrencyID
end

local function ShowEntryTooltip(self)
  local data = self.elementData
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetCurrencyByID(data.currencyID)

  if data.isAccountTransferable then
    local transferPercentage = data.transferPercentage
    local percentageLost = transferPercentage and (100 - transferPercentage) or 0
    if percentageLost > 0 then
      GameTooltip_AddNormalLine(GameTooltip, CURRENCY_TRANSFER_LOSS:format(math.ceil(percentageLost)))
    end
  end

  GameTooltip_AddBlankLineToTooltip(GameTooltip)
  GameTooltip_AddInstructionLine(GameTooltip, CURRENCY_BUTTON_TOOLTIP_CLICK_INSTRUCTION)
  GameTooltip:Show()
end

local ShowPopupFor, TogglePopupFor, SetWatched   -- forward declarations

-- Selection highlight on every result row, without a new snapshot.
local function RefreshRowHighlights()
  if not resultsBox then return end
  resultsBox:ForEachFrame(function(frame)
    if frame.RefreshHighlightVisuals then frame:RefreshHighlightVisuals() end
  end)
end

-- A plain click opens our options popup and the results stay; only the
-- popup's Transfer button ever leaves for Blizzard's list.
local function OnEntryClick(self)
  local data = self.elementData
  local linkedToChat = false
  if IsModifiedClick("CHATLINK") then
    linkedToChat = HandleModifiedItemClick(C_CurrencyInfo.GetCurrencyLink(data.currencyID))
  end
  if not linkedToChat then
    if IsModifiedClick("TOKENWATCHTOGGLE") then
      SetWatched(data, not data.isShowInBackpack)
      Refresh()   -- the row's data changed
    else
      TogglePopupFor(data)
      RefreshRowHighlights()
    end
  end

  -- Hide this currency's tooltip if we're showing the options for it.
  if EntryIsSelected(self) then
    GameTooltip_Hide()
  else
    ShowEntryTooltip(self)
  end
end

-------------------------------------------------------------------------------
-- Favorite star
--
-- Every TokenEntryTemplate row, Blizzard's and ours, gets a star button as
-- a child, created and refreshed from a hooksecurefunc post-hook on
-- TokenEntryMixin:Initialize (InstallStarHook). The star is kept in `stars`,
-- keyed by the row, never as a field on the row: a Blizzard row is only
-- read (elementData) and given a child, so its data stays clean for the
-- warband transfer path. The only other thing done to a row is moving its
-- backpack check texture onto the currency icon (widget calls, no Lua
-- writes) so the star can have the right-hand slot.
-------------------------------------------------------------------------------
-- The star reads the row's current elementData on every refresh, so a
-- pooled row stays right as Blizzard reuses it for another currency. The
-- star mode option decides whether it shows: on every row, on our result
-- rows only, or only on the row under the mouse.
local function StarShown(button)
  local mode = Config.Get(Config.Options.STAR_MODE)
  if mode == "results" then return resultRows[button] == true end
  if mode == "hover" then
    if hoveredRow == button then return true end
    -- Starred currencies may keep their star without a hover.
    local data = button.elementData
    return Config.Get(Config.Options.STAR_KEEP_FAVORITES) == true
      and data ~= nil and Favorites ~= nil and Favorites.IsFavorite(data.currencyID)
  end
  return true
end

local function RefreshStar(button)
  local star = stars[button]
  if not star then return end
  star:Refresh()
  star:SetShown(StarShown(button))
end

local function OnRowEnter(button)
  local previous = hoveredRow
  hoveredRow = button
  RefreshStar(button)
  -- Safety net: a row left through a child that swallowed its OnLeave.
  if previous and previous ~= button then RefreshStar(previous) end
end

-- Moving onto the star fires the row's OnLeave (the star is a child button
-- that takes the mouse), so the row counts as left only once the cursor is
-- outside its whole area; leaving the star runs the same check.
local function OnRowLeave(button)
  if button:IsMouseOver() then return end
  if hoveredRow == button then hoveredRow = nil end
  RefreshStar(button)
end

local function CreateStar(button)
  local star = UI.CreateFavoriteStar(button, {
    height = STAR_HEIGHT,
    point = { "LEFT", button, "LEFT", STAR_LEFT_X, 0 },
    frameLevel = button:GetFrameLevel() + 6,   -- above the row's content
    isFavorite = function()
      local data = button.elementData
      return data ~= nil and Favorites ~= nil and Favorites.IsFavorite(data.currencyID)
    end,
    onToggle = function(on)
      local data = button.elementData
      if not data then return end
      Favorites.Set(data.currencyID, on)
      if filters.favorites then
        Refresh()   -- an unstarred row leaves a Favorites-filtered list
      end
    end,
  })
  stars[button] = star

  -- Blizzard's account-wide / transferable icon appears in the left slot on
  -- hover and selection, so it moves to the right of the star (a widget
  -- anchor, no Lua write on the row). The name keeps Blizzard's own anchor
  -- to that icon, so it shifts right by the star's width and no more. Once
  -- per row frame.
  local accountIcon = button.Content.AccountWideIcon
  accountIcon:ClearAllPoints()
  accountIcon:SetPoint("LEFT", star, "RIGHT", ACCOUNT_ICON_GAP, 0)
  -- Hover tracking for the hover-only star mode; HookScript keeps the
  -- row's own handlers (Blizzard's, or ours on result rows).
  button:HookScript("OnEnter", OnRowEnter)
  button:HookScript("OnLeave", OnRowLeave)
  star:HookScript("OnLeave", function() OnRowLeave(button) end)
  -- The account-wide icon takes the mouse too, and leaving the row from it
  -- runs only Blizzard's icon OnLeave (which calls the row's mixin method,
  -- not its script), so it gets the same check.
  accountIcon:HookScript("OnLeave", function() OnRowLeave(button) end)
end

-- Post-hook on TokenEntryMixin:Initialize: runs for Blizzard's rows and
-- ours after Blizzard's own initializer. No frame is created in combat
-- (root rule); the next initialization out of combat catches up.
-- A backpack toggle from our popup is mirrored onto the row's check texture
-- until Blizzard's next rebuild (see SetWatched).
local function ApplyWatchedOverride(row)
  local data = row.elementData
  local override = data and watchedOverrides[data.currencyID]
  if override ~= nil then
    row.Content.WatchedCurrencyCheck:SetShown(override)
  end
end

local function OnEntryInitialized(row)
  if not stars[row] and not InCombatLockdown() then
    CreateStar(row)
  end
  RefreshStar(row)
  ApplyWatchedOverride(row)
end

-- Stars and backpack checks on Blizzard's rows can go stale while the
-- overlay covers them (a star clicked in the results, a backpack toggle
-- from our popup). Their frames are only read here, plus the check's
-- SetShown.
local function RefreshBlizzardStars()
  TokenFrame.ScrollBox:ForEachFrame(function(frame)
    if stars[frame] then
      RefreshStar(frame)
    end
    if frame.Content and frame.Content.WatchedCurrencyCheck then
      ApplyWatchedOverride(frame)
    end
  end)
end

local function OnEntryEnter(self)
  if not EntryIsSelected(self) then
    ShowEntryTooltip(self)
  end
  self:RefreshHighlightVisuals()
end

local function OnEntryLeave(self)
  GameTooltip_Hide()
  self:RefreshHighlightVisuals()
end

local function ToggleResultsHeader(data)
  if collapsedInResults[data.path] then
    collapsedInResults[data.path] = nil
  else
    collapsedInResults[data.path] = true
  end
  Refresh()
end

local function OnHeaderClick(header, button)
  if button == "LeftButton" then
    ToggleResultsHeader(header.elementData)
  end
end

local function OnSubHeaderToggleClick(toggle)
  ToggleResultsHeader(toggle:GetParent().elementData)
end

local OnTransferPreClick, OnTransferPostClick   -- defined under "Secure transfer hand-off"

-- Initializers. The first acquisition of a pooled frame swaps the template's
-- TokenFrame-bound scripts for ours; every acquisition then runs Blizzard's
-- own Initialize so the visuals are theirs.
local function InitEntry(button, data)
  if not button.searcherReady then
    button.searcherReady = true
    resultRows[button] = true
    button.IsSelected = EntryIsSelected
    button:SetScript("OnClick", OnEntryClick)
    button:SetScript("OnEnter", OnEntryEnter)
    button:SetScript("OnLeave", OnEntryLeave)
  end
  button:Initialize(data)   -- the mixin hook adds and refreshes the star
  if data.path and data.path ~= "" and Config.Get(Config.Options.FLAT_RESULTS) then
    -- Flat results carry their group after the name, dimmed.
    button.Content.Name:SetText(data.name .. "  " .. U.WrapColor(FLAT_GROUP_COLOR, data.path))
  end
end

local function InitHeader(header, data)
  if not header.searcherReady then
    header.searcherReady = true
    header:SetClickHandler(OnHeaderClick)
  end
  header:Initialize(data)
end

local function InitSubHeader(sub, data)
  if not sub.searcherReady then
    sub.searcherReady = true
    sub.ToggleCollapseButton:SetScript("OnClick", OnSubHeaderToggleClick)
  end
  sub:Initialize(data)
end

-------------------------------------------------------------------------------
-- Overlay construction (geometry copied from TokenFrameMixin:OnLoad and the
-- TokenFrame XML so the result is pixel-identical)
-------------------------------------------------------------------------------
-- Quantities change while the overlay is up (a transfer, a vendor), and
-- Blizzard's list only refreshes from Update, so the results refresh
-- themselves. Structural updates carry no currencyType and are ignored: the
-- snapshot's own expand and collapse must never feed back into a refresh.
local function OnCurrencyDisplayUpdate(_, _, currencyType)
  if currencyType == nil or not IsSearchActive() then return end
  refreshQuantities:Call()
end
refreshQuantities = U.Coalesce(DEBOUNCE_SECONDS, function()
  if IsSearchActive() and TokenFrame:IsShown() then
    Refresh()
  end
end)

local function BuildOverlay()
  local blizzBox = TokenFrame.ScrollBox
  local blizzBar = TokenFrame.ScrollBar

  overlay = CreateFrame("Frame", "CobysCurrencySearcherResults", TokenFrame)
  -- Top, left and bottom from the box (the bar ends 4px above it), right
  -- from the bar, so every faded Blizzard pixel is under our mouse shield.
  overlay:SetPoint("TOPLEFT", blizzBox, "TOPLEFT", 0, 0)
  overlay:SetPoint("BOTTOMLEFT", blizzBox, "BOTTOMLEFT", 0, 0)
  overlay:SetPoint("RIGHT", blizzBar, "RIGHT", 0, 0)
  overlay:SetFrameStrata(blizzBox:GetFrameStrata())
  overlay:SetFrameLevel(blizzBox:GetFrameLevel() + 20)
  overlay:EnableMouse(true)   -- swallow clicks so the faded list below gets none
  overlay:Hide()
  overlay:SetScript("OnShow", function(self) self:RegisterEvent("CURRENCY_DISPLAY_UPDATE") end)
  overlay:SetScript("OnHide", function(self)
    self:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
    refreshQuantities:Cancel()
  end)
  overlay:SetScript("OnEvent", OnCurrencyDisplayUpdate)

  resultsBox = CreateFrame("Frame", nil, overlay, "WowScrollBoxList")
  resultsBox:SetAllPoints(blizzBox)
  resultsBox:SetFrameLevel(overlay:GetFrameLevel() + 1)

  resultsBar = CreateFrame("EventFrame", nil, overlay, "MinimalScrollBar")
  resultsBar:SetAllPoints(blizzBar)
  resultsBar:SetFrameLevel(overlay:GetFrameLevel() + 1)

  local view = CreateScrollBoxListLinearView()
  view:SetElementIndentCalculator(function(elementData)
    local isTopLevelHeader = elementData.isHeader and elementData.currencyListDepth == 0
    if isTopLevelHeader or Config.Get(Config.Options.FLAT_RESULTS) then
      return 0
    end
    -- We only slightly indent elements that are immediately under top level headers
    if elementData.currencyListDepth == 1 then
      return 2
    end
    return 50 * (elementData.currencyListDepth - 1)
  end)
  view:SetElementFactory(function(factory, elementData)
    local isTopLevelHeader = elementData.isHeader and elementData.currencyListDepth == 0
    if isTopLevelHeader then
      factory("TokenHeaderTemplate", InitHeader)
      return
    end
    local isSubHeader = elementData.isHeader and elementData.currencyListDepth > 0
    if isSubHeader then
      factory("TokenSubHeaderTemplate", InitSubHeader)
      return
    end
    factory("TokenEntryTemplate", InitEntry)
  end)
  view:SetPadding(LIST_PADDING, LIST_PADDING, LIST_PADDING, LIST_PADDING, LIST_SPACING)
  ScrollUtil.InitScrollBoxListWithScrollBar(resultsBox, resultsBar, view)

  local label = overlay:CreateFontString(nil, "OVERLAY", U.Fonts.BODY)
  label:SetPoint("CENTER", resultsBox, "CENTER", 0, 0)
  label:SetWidth(EMPTY_LABEL_WIDTH)
  label:SetJustifyH("CENTER")
  local gray = U.Colors.LABEL_GRAY
  label:SetTextColor(gray[1], gray[2], gray[3])
  label:SetText("No matching currencies")
  label:Hide()
  emptyLabel = label
end

local function ShowOverlay()
  -- Alpha is a C-side property: no scripts run and no Lua fields change on
  -- Blizzard's frames.
  TokenFrame.ScrollBox:SetAlpha(0)
  TokenFrame.ScrollBar:SetAlpha(0)
  -- Blizzard's options popup shares our popup's anchor. Hide() is C-side
  -- and its OnHide only plays a sound; Blizzard's selection fields are
  -- left alone.
  if TokenFramePopup and TokenFramePopup:IsShown() then
    TokenFramePopup:Hide()
  end
  overlay:Show()
end

local function HideOverlay()
  if popup then popup:Hide() end
  overlay:Hide()
  TokenFrame.ScrollBox:SetAlpha(1)
  TokenFrame.ScrollBar:SetAlpha(1)
  SetEmptyLabelShown(false)
  RefreshBlizzardStars()
end

-------------------------------------------------------------------------------
-- Options popup (replica of TokenFramePopup)
--
-- Unused and Show on Backpack work from here. Transfer cannot start here:
-- its button runs the secure hand-off to Blizzard's clean list, the only
-- place a transfer can start (see the file header and "Secure transfer
-- hand-off").
-------------------------------------------------------------------------------
local TRANSFER_DISABLED_MESSAGES   -- built on first use (mirrors Blizzard_CurrencyTransfer.lua)

local function TransferDisabledMessage(dataReady, failureReason)
  if not dataReady then
    return RETRIEVING_DATA
  end
  if not TRANSFER_DISABLED_MESSAGES then
    local E = Enum.AccountCurrencyTransferResult
    TRANSFER_DISABLED_MESSAGES = {
      [E.MaxQuantity] = CURRENCY_TRANSFER_DISABLED_MAX_QUANTITY,
      [E.NoValidSourceCharacter] = CURRENCY_TRANSFER_DISABLED_NO_VALID_SOURCES,
      [E.CannotUseCurrency] = CURRENCY_TRANSFER_DISABLED_UNMET_REQUIREMENTS,
      [E.TransactionInProgress] = CURRENCY_TRANSFER_IN_PROGRESS,
      [E.CurrencyTransferDisabled] = ERR_CURRENCY_TRANSFER_DISABLED,
    }
  end
  return failureReason and TRANSFER_DISABLED_MESSAGES[failureReason] or nil
end

local TRANSFER_HANDOFF_TOOLTIP = "Opens the transfer menu for this currency. Your search stays. In combat, only Blizzard's list comes back."

local function RefreshTransferButton(data)
  local button = popup.TransferButton
  local currencyID = data.currencyID
  local dataReady = C_CurrencyInfo.IsAccountCharacterCurrencyDataReady()
  local canTransfer, failureReason = C_CurrencyInfo.CanTransferCurrency(currencyID)
  local isValidCurrency = C_CurrencyInfo.IsAccountTransferableCurrency(currencyID)

  if not dataReady then
    -- Same request Blizzard's toggle makes on show; the received event
    -- refreshes us through the popup's own event handler.
    C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
  end

  button:SetEnabled(dataReady and canTransfer)
  button:SetDisabledTooltip(TransferDisabledMessage(dataReady, failureReason), "ANCHOR_RIGHT")
  local hasDisabledTooltip = button:GetDisabledTooltip() ~= nil
  button:SetShown(button:IsEnabled() or (isValidCurrency and hasDisabledTooltip))
  -- The secure clicker only covers an enabled button, so the disabled
  -- tooltip still works.
  if button.clicker then
    button.clicker:SetShown(button:IsEnabled())
  end
end

local function PopupBestHeight()
  local showingCheckboxes = popup.InactiveCheckbox:IsShown() or popup.BackpackCheckbox:IsShown()
  local showingTransfer = popup.TransferButton:IsShown()
  if showingCheckboxes and showingTransfer then
    return POPUP_HEIGHT_FULL
  elseif showingTransfer then
    return POPUP_HEIGHT_TRANSFER_ONLY
  end
  return POPUP_HEIGHT_DEFAULT
end

RefreshPopup = function(data)
  popup.InactiveCheckbox:SetShown(data.discovered)
  popup.InactiveCheckbox:SetChecked(data.isTypeUnused)
  popup.BackpackCheckbox:SetShown(data.discovered)
  popup.BackpackCheckbox:SetChecked(data.isShowInBackpack)
  RefreshTransferButton(data)
  popup:SetHeight(PopupBestHeight())
end

ShowPopupFor = function(data)
  selectedCurrencyID = data.currencyID
  RefreshPopup(data)
  popup:Show()
end

TogglePopupFor = function(data)
  if popup:IsShown() and selectedCurrencyID == data.currencyID then
    popup:Hide()
    return
  end
  ShowPopupFor(data)
end

-- Mirrors BackpackTokenFrameMixin:GetMaxTokensWatched and GetNumWatchedTokens
-- with C-side reads only. The Blizzard methods write fields on the backpack
-- bar (and can run its Update) under our taint, and the bag frames read that
-- state on paths that reach protected item functions.
local function MaxWatchedTokens()
  local info = C_XMLUtil.GetTemplateInfo("BackpackTokenTemplate")
  local tokenWidth = info and info.width or 50
  local width = BackpackTokenFrame and BackpackTokenFrame:GetWidth() or 0
  if width <= 1 and ContainerFrame_GetApproximateWidth then
    -- Backpack never opened since UI load; Blizzard estimates the same way.
    width = ContainerFrame_GetApproximateWidth()
  end
  return math.max(math.floor(width / tokenWidth), 1)
end

local function NumWatchedTokens(maxWatched)
  local n = 0
  for i = 1, maxWatched do
    if C_CurrencyInfo.GetBackpackCurrencyInfo(i) then
      n = i
    end
  end
  return n
end

-- Show on Backpack. By currency id, so no list index is needed and Blizzard's
-- hidden list stays consistent (row order does not change). The backpack bar
-- refreshes itself from the game's currency events; we never call its Update
-- from addon code because the bag frames read its state on protected paths.
SetWatched = function(data, watched)
  if watched then
    local maxWatched = MaxWatchedTokens()
    if NumWatchedTokens(maxWatched) >= maxWatched then
      UIErrorsFrame:AddMessage(TOO_MANY_WATCHED_TOKENS:format(maxWatched), 1.0, 0.1, 0.1, 1.0)
      return false
    end
  end
  C_CurrencyInfo.SetCurrencyBackpackByID(data.currencyID, watched)
  -- Blizzard's hidden rows keep the old check until their next rebuild, and
  -- a rebuild from addon code would taint them for transfers (see the
  -- file header), so the check texture is overridden instead: a widget call,
  -- no Lua write, applied by the row hook and dropped at the next rebuild.
  -- Their elementData stays stale until then, so the first modified click
  -- on that row in Blizzard's list toggles against the old value.
  watchedOverrides[data.currencyID] = watched
  Debug.Log("SEARCH", "%s %s on backpack", watched and "Showing" or "Hiding", data.name or "?")
  return true
end

-- Unused. Only exists by list index, so it runs against the fully expanded
-- list. Marking a currency unused moves it into the Unused group, which
-- reorders the game's list underneath Blizzard's hidden rows; that is the one
-- action here that leaves their list stale, so the next search clear rebuilds
-- it (see SetQuery). Blizzard's own list goes stale the same way whenever a
-- currency is discovered while the tab is open.
local function SetUnused(data, unused)
  local applied = WithExpandedIndex(data.currencyID, function(index)
    C_CurrencyInfo.SetCurrencyUnused(index, unused)
  end)
  if applied then
    blizzardListStale = true
    Debug.Log("SEARCH", "%s marked %s", data.name or "?", unused and "unused" or "used")
  else
    Debug.Warn("SEARCH", "Could not find %s in the expanded list to change its unused state", data.name or "?")
  end
end

local function OnInactiveClick(checkbox)
  local data = FindResult(selectedCurrencyID)
  if not data then return end
  local unused = checkbox:GetChecked()
  PlaySound(unused and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  SetUnused(data, unused)
  Refresh()
end

local function OnBackpackClick(checkbox)
  local data = FindResult(selectedCurrencyID)
  if not data then return end
  local watched = checkbox:GetChecked()
  if not SetWatched(data, watched) then
    checkbox:SetChecked(false)
    return
  end
  PlaySound(watched and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
  Refresh()
end

local function BuildPopup()
  local f = CreateFrame("Frame", "CobysCurrencySearcherCurrencyPopup", TokenFrame)
  f:SetSize(POPUP_WIDTH, POPUP_HEIGHT_DEFAULT)
  f:SetPoint("TOPLEFT", TokenFrame, "TOPRIGHT", 3, -28)
  f:SetFrameStrata(TokenFrame:GetFrameStrata())
  f:SetFrameLevel(TokenFrame:GetFrameLevel() + 30)
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:Hide()

  f.Border = CreateFrame("Frame", nil, f, "SecureDialogBorderTemplate")
  f.Border:SetAllPoints()

  f.Title = f:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
  f.Title:SetPoint("TOPLEFT", 25, -17)
  f.Title:SetText(TOKEN_OPTIONS)

  local inactive = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  inactive:SetSize(26, 26)
  inactive:SetPoint("TOPLEFT", f.Title, "BOTTOMLEFT", -5, -5)
  inactive.Text:SetText(UNUSED)
  inactive.Text:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
  inactive:SetScript("OnClick", OnInactiveClick)
  inactive:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_AddNormalLine(GameTooltip, TOKEN_MOVE_TO_UNUSED)
    GameTooltip:Show()
  end)
  inactive:SetScript("OnLeave", GameTooltip_Hide)
  f.InactiveCheckbox = inactive

  local backpack = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  backpack:SetSize(26, 26)
  backpack:SetPoint("TOPLEFT", inactive, "BOTTOMLEFT", 0, 4)
  backpack.Text:SetText(SHOW_ON_BACKPACK)
  backpack.Text:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
  backpack:SetScript("OnClick", OnBackpackClick)
  backpack:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_AddNormalLine(GameTooltip, TOKEN_SHOW_ON_BACKPACK)
    GameTooltip:Show()
  end)
  backpack:SetScript("OnLeave", GameTooltip_Hide)
  f.BackpackCheckbox = backpack

  -- Same templates as CurrencyTransferToggleButtonTemplate, minus its mixin
  -- scripts, which drive the real transfer menu.
  local transfer = CreateFrame("Button", nil, f, "UIPanelButtonTemplate, DisabledTooltipButtonTemplate")
  transfer:SetSize(120, 22)
  transfer:SetPoint("LEFT", 23, 0)
  transfer:SetPoint("BOTTOM", 0, 25)
  transfer:SetText(CURRENCY_TRANSFER_TOGGLE_BUTTON_LABEL)
  transfer:HookScript("OnEnter", function(self)
    if not self:IsEnabled() then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(TRANSFER_HANDOFF_TOOLTIP, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  transfer:HookScript("OnLeave", GameTooltip_Hide)
  f.TransferButton = transfer

  -- Full-size insecure action button over Transfer. Its OnClick is
  -- Blizzard's secure action handler, so TRANSFER_MACRO runs on a secure
  -- path (see "Secure transfer hand-off"). Mouse events are forwarded so
  -- the button underneath still presses, highlights and shows its tooltip.
  local clicker = CreateFrame("Button", nil, transfer, "InsecureActionButtonTemplate")
  clicker:SetAllPoints()
  clicker:SetFrameLevel(transfer:GetFrameLevel() + 5)
  clicker:RegisterForClicks("LeftButtonUp")
  clicker:SetAttribute("useOnKeyDown", false)
  clicker:SetAttribute("type", "macro")
  clicker:SetAttribute("macrotext", TRANSFER_MACRO)
  -- Modified clicks never run the macro.
  clicker:SetAttribute("shift-type*", "")
  clicker:SetAttribute("ctrl-type*", "")
  clicker:SetAttribute("alt-type*", "")
  clicker:SetScript("PreClick", OnTransferPreClick)
  clicker:SetScript("PostClick", OnTransferPostClick)
  local function Forward(script)
    return function(_, ...)
      local handler = transfer:GetScript(script)
      if handler then handler(transfer, ...) end
    end
  end
  clicker:SetScript("OnEnter", Forward("OnEnter"))
  clicker:SetScript("OnLeave", Forward("OnLeave"))
  clicker:SetScript("OnMouseDown", Forward("OnMouseDown"))
  clicker:SetScript("OnMouseUp", Forward("OnMouseUp"))
  transfer.clicker = clicker

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() f:Hide() end)
  f.CloseButton = close

  f:SetScript("OnShow", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    f:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    f:RegisterEvent("CURRENCY_TRANSFER_INITIATED")
    f:RegisterEvent("CURRENCY_TRANSFER_SUCCESS")
    f:RegisterEvent("CURRENCY_TRANSFER_FAILED")
  end)
  f:SetScript("OnHide", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    f:UnregisterAllEvents()
    selectedCurrencyID = nil
    RefreshRowHighlights()
  end)
  f:SetScript("OnEvent", function()
    local data = FindResult(selectedCurrencyID)
    if data then RefreshTransferButton(data); f:SetHeight(PopupBestHeight()) end
  end)

  return f
end

-------------------------------------------------------------------------------
-- Query lifecycle
-------------------------------------------------------------------------------
-- Shows, refreshes or clears the results after the search text or a filter
-- changed. Idempotent: only a change of IsSearchActive() shows or hides the
-- overlay.
local function ApplySearchState()
  if not IsSearchActive() then
    if not overlayActive then return end
    overlayActive = false
    wipe(collapsedInResults)
    lastResults = nil
    HideOverlay()
    Debug.State("SEARCH", "Search cleared")
    if blizzardListStale and TokenFrame:IsShown() then
      -- The only addon-triggered rebuild of Blizzard's list, and only after
      -- our popup reordered the game's list (Unused). Rows built here carry
      -- addon taint until the tab is reopened, which matters only for the
      -- warband transfer confirm button; a stale list would be worse, since
      -- its indices would point at the wrong currencies.
      blizzardListStale = false
      TokenFrame:Update()
      Debug.Warn("SEARCH", "Rebuilt Blizzard's list after an Unused change; reopen the tab before transferring")
    end
    return
  end

  if not overlayActive then
    overlayActive = true
    Debug.State("SEARCH", "Search started")
    ShowOverlay()
  end
  if TokenFrame:IsShown() then
    Refresh()
    resultsBox:ScrollToBegin()
  end
end

local function SetQuery(text)
  local newQuery = strlower(strtrim(text or ""))
  if newQuery == query then return end
  query = newQuery
  ApplySearchState()
end

-- Filters last for the session by default. With the FILTERS_PERSIST option
-- on, every change is also written to SAVED_FILTERS (a fresh table each
-- time; the saved one is never edited in place) and LoadPersistedFilters
-- puts the set back at the next login.
local function PersistFilters()
  if not Config.Get(Config.Options.FILTERS_PERSIST) then return end
  local saved = {}
  for key, on in pairs(filters) do
    saved[key] = on
  end
  Config.Set(Config.Options.SAVED_FILTERS, saved)
end

local function SetFilter(key, on)
  on = on and true or nil
  if filters[key] == on then return end
  filters[key] = on
  Debug.State("SEARCH", "Filter '%s' %s", key, on and "on" or "off")
  RefreshFilterUI()
  PersistFilters()
  ApplySearchState()
end

local function ClearFilters()
  if not AnyFilterActive() then return end
  wipe(filters)
  Debug.State("SEARCH", "Filters cleared")
  RefreshFilterUI()
  PersistFilters()
  ApplySearchState()
end

-- Runs once, after this addon's SavedVariables have loaded and before the
-- tab has shown: the overlay state is set up here and the tab's first
-- OnShow Update draws the filtered results.
local function LoadPersistedFilters()
  if not Config.Get(Config.Options.FILTERS_PERSIST) then return end
  local saved = Config.Get(Config.Options.SAVED_FILTERS)
  local loaded = {}
  for _, def in ipairs(FILTER_DEFS) do   -- only keys that still exist
    if saved[def.key] then
      filters[def.key] = true
      loaded[#loaded + 1] = def.key
    end
  end
  if #loaded == 0 then return end
  Debug.State("SEARCH", "Filters restored from the last session: %s", table.concat(loaded, ", "))
  RefreshFilterUI()
  ApplySearchState()
end

-- The search box debounces its own text (CobySuite.UI.CreateSearchBox); a
-- pending apply is dropped whenever the search is cleared or restored by
-- code, so it cannot land after the fact.
local function CancelPendingSearch()
  if searchBox then searchBox:CancelPendingSearch() end
end

-------------------------------------------------------------------------------
-- Secure transfer hand-off
--
-- Our popup's Transfer button carries an InsecureActionButtonTemplate child
-- whose OnClick is Blizzard's SecureActionButton_OnClick, so TRANSFER_MACRO
-- runs on a secure path: it flips the character window away from and back
-- to the Currency tab (TokenFrame's own OnShow rebuilds the list with clean
-- rows), /clicks CobysCurrencySearcherClickStep, a click-type delegate that
-- the Update post-hook has aimed at the target's row (Blizzard's row OnClick
-- opens Blizzard's real popup and runs Update again), then /clicks
-- CobysCurrencySearcherTransferStep, a second delegate that the same hook
-- aims at the popup's transfer toggle once the popup is open for the
-- target. Blizzard's transfer menu opens with clean data, and the transfer
-- works from it. The row step was verified in-game on 2026-09-08, the
-- toggle step on 2026-09-09.
--
-- Before the macro, PreClick stashes the search (text and filters), clears
-- it, records the user's collapse state (restored when the tab hides) and
-- folds every header except the target's chain, so the rebuilt list has the
-- target within its first screen of rows. There is no secure way to scroll
-- Blizzard's list, so a target that still lands below the first screen is
-- reported instead. Once the transfer menu is open for the target (Blizzard
-- hides its own options popup as the menu opens, so the popup is no sign of
-- success), PostClick puts the stashed search straight back, all within the
-- same click, so the user never sees Blizzard's list: the overlay covers it
-- while the menu, a separate window with its own currency and source state
-- set on the secure path, stays open beside the window. Blizzard hides that
-- menu only from TokenFrame:Update, which the overlay never calls.
-------------------------------------------------------------------------------
local function ArmClickStep(row)
  if clickStep then
    clickStep:SetAttribute("clickbutton", row)
  end
end

local function ArmTransferStep(button)
  if transferStep then
    transferStep:SetAttribute("clickbutton", button)
  end
end

-- Blizzard's list has the currency selected (its row was clicked).
local function SelectedCurrencyIs(currencyID)
  if not TokenFrame.selectedID then return false end
  local info = C_CurrencyInfo.GetCurrencyListInfo(TokenFrame.selectedID)
  return info ~= nil and info.currencyID == currencyID
end

local function PopupOpenFor(currencyID)
  return TokenFramePopup ~= nil and TokenFramePopup:IsShown() and SelectedCurrencyIs(currencyID)
end

local function TransferMenuOpenFor(currencyID)
  return CurrencyTransferMenu ~= nil and CurrencyTransferMenu:IsShown()
    and CurrencyTransferMenu:GetCurrencyID() == currencyID
end

-- Clears the search text and the filters at once. The box's OnTextChanged
-- can arrive a frame later; ApplySearchState is idempotent, so that is
-- harmless.
local function ClearSearchNow()
  CancelPendingSearch()
  if filterButton then filterButton.Menu:Hide() end
  if AnyFilterActive() then
    wipe(filters)
    RefreshFilterUI()
    PersistFilters()
  end
  if searchBox and searchBox:GetText() ~= "" then
    searchBox:SetText("")
  end
  query = ""
  ApplySearchState()
end

local function StashSearch()
  local stash = {
    text = searchBox and searchBox:GetText() or "",
    filters = {},
    scroll = resultsBox and resultsBox:GetScrollPercentage() or 0,
  }
  for key, on in pairs(filters) do
    stash.filters[key] = on
  end
  stashedSearch = stash
end

-- Puts the stashed search back over Blizzard's list. A no-op once the tab
-- is hidden: its OnHide clears the search anyway, and the stash with it.
local function RestoreSearch()
  local stash = stashedSearch
  stashedSearch = nil
  if not stash or not searchBox or not TokenFrame:IsVisible() then return end
  wipe(filters)
  for key, on in pairs(stash.filters) do
    filters[key] = on
  end
  RefreshFilterUI()
  PersistFilters()
  CancelPendingSearch()
  searchBox:SetText(stash.text)   -- OnTextChanged schedules the same query; harmless
  query = strlower(strtrim(stash.text))
  ApplySearchState()   -- refreshes the results and scrolls them to the top
  if resultsBox then
    -- Back to where the user was: the row they clicked Transfer on.
    resultsBox:SetScrollPercentage(stash.scroll, ScrollBoxConstants.NoScrollInterpolation)
  end
  Debug.State("SEARCH", "Search restored with the transfer menu open: %s", SearchDescription())
end

-- In combat the insecure template refuses, so the hand-off is by hand: the
-- search clears and the user clicks the currency in Blizzard's list.
local function TransferHandoffInCombat(data)
  local where = (data.path and data.path ~= "") and (" under " .. data.path) or ""
  Utilities.Message(("In combat, transfers start from Blizzard's list: click %s there%s."):format(data.name or "this currency", where))
  Debug.Log("SEARCH", "Transfer hand-off in combat for %s", data.name or "?")
  ClearSearchNow()
end

-- Runs before the secure action. Modified clicks and clicks in combat never
-- reach the macro (the modifier attributes are no-ops and the insecure
-- template refuses in combat).
OnTransferPreClick = function()
  local data = FindResult(selectedCurrencyID)
  if not data then return end
  if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then
    return   -- modified click; the macro is a no-op for it too
  end
  if InCombatLockdown() then
    TransferHandoffInCombat(data)
    return
  end

  macroTarget = {
    currencyID = data.currencyID,
    name = data.name,
    path = data.path,
    ancestors = data.ancestors or {},
  }
  macroInFlight = true
  -- Remember the collapse state from before the first hand-off so the tab's
  -- OnHide can put it back; later hand-offs keep the earliest record.
  if not restoreCollapsedKeys then
    restoreCollapsedKeys = {}
    for key in pairs(lastCollapsedKeys or {}) do
      restoreCollapsedKeys[key] = true
    end
  end
  StashSearch()
  ClearSearchNow()   -- hides the overlay and our popup
  GameTooltip_Hide()
  CollapseAllExcept(macroTarget.ancestors)
  ArmClickStep(nil)
  ArmTransferStep(nil)
  Debug.State("SEARCH", "Transfer: selecting %s in Blizzard's list", data.name or "?")
end

OnTransferPostClick = function()
  if not macroInFlight then return end
  macroInFlight = false
  ArmClickStep(nil)
  ArmTransferStep(nil)
  local target = macroTarget
  macroTarget = nil
  if not target then return end
  if TransferMenuOpenFor(target.currencyID) then
    -- Blizzard hides its own options popup once the menu is open, so the
    -- menu, not the popup, is the sign that every macro line landed.
    Debug.Log("SEARCH", "%s selected and the transfer menu is open", target.name or "?")
    RestoreSearch()
    return
  end
  if SelectedCurrencyIs(target.currencyID) then
    -- The row was clicked but the toggle did not open the menu (no longer
    -- transferable); the user stays on Blizzard's popup.
    stashedSearch = nil
    Debug.Warn("SEARCH", "%s selected but the transfer menu did not open", target.name or "?")
    return
  end
  -- The rebuilt list did not put the row on screen (it sits below the first
  -- screen even with every other header folded). The list is left folded
  -- around it so it is a short scroll away.
  stashedSearch = nil
  local where = (target.path and target.path ~= "") and (" under " .. target.path) or ""
  Utilities.Message(("%s is%s. Scroll down to it and click it; the rest of the list is folded."):format(target.name or "That currency", where))
  Debug.Warn("SEARCH", "Transfer: %s was not within the first screen after the rebuild", target.name or "?")
end

-- Post-hook on TokenFrame:Update(). Blizzard has just rebuilt its list from
-- fresh data. During a hand-off, aim the row delegate at the target's row,
-- then, once Blizzard's popup is open for it, aim the transfer delegate at
-- the popup's toggle; otherwise refresh our results from the same data.
-- Their frames are only ever read.
local function OnTokenFrameUpdated()
  blizzardListStale = false   -- any rebuild, theirs or ours, is fresh
  wipe(watchedOverrides)      -- the rebuilt rows carry the real backpack state
  if macroInFlight and macroTarget then
    if PopupOpenFor(macroTarget.currencyID) then
      -- The row step has clicked the row (its OnClick runs Update): the
      -- last macro line clicks the transfer toggle.
      ArmClickStep(nil)
      ArmTransferStep(TokenFramePopup.CurrencyTransferToggleButton)
    else
      local id = macroTarget.currencyID
      local row = TokenFrame.ScrollBox:FindFrameByPredicate(function(frame, elementData)
        return elementData ~= nil and not elementData.isHeader and elementData.currencyID == id
      end)
      ArmClickStep(row)
      ArmTransferStep(nil)
    end
    return
  end
  if not IsSearchActive() then return end
  ShowOverlay()   -- re-assert the fade; harmless when already applied
  Refresh()
end

-- Clears the search text (unless the keep-text option is on); filters stay
-- on for the session, so a tab reopened with a filter on shows the filtered
-- list at once (Blizzard's OnShow Update reaches OnTokenFrameUpdated).
local function OnTokenFrameHidden()
  if filterButton then filterButton.Menu:Hide() end
  if macroInFlight then return end   -- the tab detour of a transfer hand-off
  stashedSearch = nil
  if not Config.Get(Config.Options.KEEP_TEXT) then
    CancelPendingSearch()
    if searchBox and searchBox:GetText() ~= "" then
      -- SetText("") fires OnTextChanged, which routes through SetQuery("").
      SearchBoxTemplate_ClearText(searchBox)
    elseif query ~= "" then
      SetQuery("")
    end
  end
  RestoreCollapseState()
end

-------------------------------------------------------------------------------
-- Search box
--
-- CobySuite.UI.CreateSearchBox: Blizzard's SearchBoxTemplate as a live,
-- debounced filter. An empty box applies at once, so it always means "no
-- search", including programmatic clears (clear button, OnHide).
-------------------------------------------------------------------------------
local function BuildSearchBox()
  return UI.CreateSearchBox(TokenFrame, {
    name = "CobysCurrencySearcherSearchBox",
    width = BOX_WIDTH,
    -- One anchor: the vertical center comes from Blizzard's dropdown through
    -- the two icons, and the left edge lands at x = 53, clear of the
    -- character portrait.
    point = { "RIGHT", filterButton, "LEFT", -BOX_GAP, 0 },
    maxLetters = MAX_LETTERS,
    debounce = DEBOUNCE_SECONDS,   -- the saved delay is applied once SavedVariables exist (Setup)
    onSearch = function(text) SetQuery(text) end,
  })
end

-------------------------------------------------------------------------------
-- Filter button, settings gear
--
-- The funnel and its checkbox menu are CobySuite.UI.CreateFilterButton (the
-- taint-isolated menu; Blizzard's pooled Menu frames are shared with the
-- transfer menu on this tab). The gear beside it opens the settings window.
-------------------------------------------------------------------------------
RefreshFilterUI = function()
  if filterButton then filterButton:Refresh() end
end

local function BuildSettingsButton()
  return UI.CreateFilterStyleButton(TokenFrame, {
    name = "CobysCurrencySearcherSettingsButton",
    -- Vertical center from Blizzard's dropdown, like the funnel and the box.
    point = { "RIGHT", TokenFrame.filterDropdown, "LEFT", -DROPDOWN_GAP, 0 },
    glyphAtlas = SETTINGS_GLYPH_ATLAS,
    glyphInset = SETTINGS_GLYPH_INSET,
    tooltip = "Settings",
    onClick = function()
      PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
      Config.ToggleSettings()
    end,
  })
end

local function BuildFilterButton()
  return UI.CreateFilterButton(TokenFrame, {
    name = "CobysCurrencySearcherFilterButton",
    -- Vertical center from Blizzard's dropdown through the settings gear.
    point = { "RIGHT", settingsButton, "LEFT", -ICON_GAP, 0 },
    defs = FILTER_DEFS,
    isChecked = function(key) return filters[key] == true end,
    setChecked = SetFilter,
    onClear = ClearFilters,
    tooltipIdle = "Narrow the list, with or without search text.",
    menu = { name = "CobysCurrencySearcherFilterMenu", parent = TokenFrame },
  })
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
local function Setup()
  if searchBox then return end

  if InCombatLockdown() then
    Debug.State("INIT", "In combat at setup; installing the search box after combat")
    EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_REGEN_ENABLED", Setup)
    return
  end

  if not (TokenFrame and TokenFrame.ScrollBox and TokenFrame.ScrollBar
          and TokenFrame.filterDropdown and TokenFrame.Update) then
    Debug.Warn("INIT", "TokenFrame is missing or changed shape; search box not installed")
    return
  end

  if not Favorites then
    -- Only ever seen in development: a file added to the TOC is not read
    -- by /reload, so Favorites/Main.lua has not loaded yet.
    Debug.Warn("INIT", "Favorites module missing; the TOC was not re-read. Log out and back in")
    Utilities.Message("The Favorites module did not load. Log out to the character screen and back in.")
  end

  BuildOverlay()
  popup = BuildPopup()
  settingsButton = BuildSettingsButton()
  filterButton = BuildFilterButton()
  searchBox = BuildSearchBox()

  -- The /click delegates of TRANSFER_MACRO (see "Secure transfer hand-off").
  -- Created once each: GetClickFrame caches the first object registered
  -- under a name.
  local function CreateDelegate(name)
    local delegate = CreateFrame("Button", name, UIParent, "InsecureActionButtonTemplate")
    delegate:SetSize(1, 1)
    delegate:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    delegate:SetAlpha(0)
    delegate:RegisterForClicks("LeftButtonUp")
    delegate:SetAttribute("useOnKeyDown", false)
    delegate:SetAttribute("type", "click")
    return delegate
  end
  clickStep = CreateDelegate("CobysCurrencySearcherClickStep")
  transferStep = CreateDelegate("CobysCurrencySearcherTransferStep")

  -- Hook the frame instance: the mixin methods are copied onto the frame,
  -- and every internal call goes through TokenFrame:Update(). The hook only
  -- refreshes our results (and aims the delegates during a hand-off).
  hooksecurefunc(TokenFrame, "Update", OnTokenFrameUpdated)
  TokenFrame:HookScript("OnHide", OnTokenFrameHidden)
  TokenFrame:HookScript("OnShow", function()
    -- Not during the transfer hand-off's tab detour.
    if not macroInFlight and Config.Get(Config.Options.FOCUS_ON_OPEN) then
      searchBox:SetFocus()
    end
  end)

  CobysCurrencySearcher.EventBus:Register(Search, { CobysCurrencySearcher.Events.ConfigChanged })
  -- Setup runs while Blizzard_TokenUI loads, before this addon's own
  -- SavedVariables exist; the saved search delay and the persisted filters
  -- can only be read after our ADDON_LOADED (immediately when Setup was
  -- deferred past it).
  EventUtil.ContinueOnAddOnLoaded("CobysCurrencySearcher", function()
    searchBox:SetSearchDelay(Config.Get(Config.Options.SEARCH_DELAY))
    LoadPersistedFilters()
  end)

  Debug.Log("INIT", "Search box, filter icon, settings gear and results list installed on the Currency tab")
end

-- Blizzard_TokenUI is not load-on-demand, but ContinueOnAddOnLoaded runs the
-- callback immediately when it is already loaded and waits otherwise, so it
-- is the safe way to sequence against it.
EventUtil.ContinueOnAddOnLoaded("Blizzard_TokenUI", Setup)

-- Star hook, installed as soon as Blizzard_TokenUI is loaded and without a
-- combat gate (nothing is created here). Mixin copies the hooked function
-- into every row created after this point, Blizzard's and ours, so each
-- row gets its star on first use and a refresh on every reuse.
local function InstallStarHook()
  if TokenEntryMixin and TokenEntryMixin.Initialize then
    hooksecurefunc(TokenEntryMixin, "Initialize", OnEntryInitialized)
  else
    Debug.Warn("INIT", "TokenEntryMixin is missing or changed shape; favorite stars not installed")
  end
end
EventUtil.ContinueOnAddOnLoaded("Blizzard_TokenUI", InstallStarHook)

-------------------------------------------------------------------------------
-- EventBus
-------------------------------------------------------------------------------
function Search:ReceiveEvent(eventName, optionName)
  if eventName ~= CobysCurrencySearcher.Events.ConfigChanged then return end
  if optionName == Config.Options.SAVED_FILTERS then return end   -- our own write
  -- Persistence switched: start saving the current set, or forget the saved one.
  if optionName == nil or optionName == Config.Options.FILTERS_PERSIST then
    if Config.Get(Config.Options.FILTERS_PERSIST) then
      PersistFilters()
    elseif next(Config.Get(Config.Options.SAVED_FILTERS)) ~= nil then
      Config.Set(Config.Options.SAVED_FILTERS, {})
    end
  end
  if optionName == nil or optionName == Config.Options.SEARCH_DELAY then
    if searchBox then searchBox:SetSearchDelay(Config.Get(Config.Options.SEARCH_DELAY)) end
  end
  local starOption = optionName == Config.Options.STAR_MODE or optionName == Config.Options.STAR_KEEP_FAVORITES
  if optionName == nil or starOption then
    hoveredRow = nil
    RefreshBlizzardStars()
  end
  -- Re-filter when an option that shapes the results flips during a search.
  if (optionName == nil or optionName == Config.Options.MATCH_DESCRIPTIONS
      or optionName == Config.Options.FLAT_RESULTS or starOption)
      and IsSearchActive() and TokenFrame:IsShown() then
    Refresh()
  end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Opens the Currency tab if needed and searches for `text`. The open goes
-- through ShowUIPanel, which shows the window on a secure path even when we
-- call it, so the rows Blizzard builds on that OnShow are clean (verified
-- in-game 2026-09-08: a transfer from a row of a tab opened this way works).
-- ShowSubFrame on an already-open window would show the tab inside our
-- execution instead, so the window is closed first in that case.
function Search.OpenAndSearch(text)
  if not searchBox then
    Debug.Warn("SEARCH", "/ccs refused: search box not installed")
    Utilities.Message("The Currency tab search box is not available.")
    return
  end
  text = strtrim(text or "")
  -- IsVisible, not IsShown: the tab can be shown inside a hidden character
  -- frame.
  if not TokenFrame:IsVisible() then
    if CharacterFrame:IsShown() then
      HideUIPanel(CharacterFrame)
    end
    ToggleCharacter("TokenFrame", true)
  end
  if not TokenFrame:IsVisible() then
    -- ToggleCharacter is a no-op under the CharacterPanelDisabled game rule
    -- and ShowUIPanel can refuse the panel.
    Debug.Warn("SEARCH", "/ccs refused: the Currency tab could not be opened")
    Utilities.Message("The Currency tab could not be opened here.")
    return
  end
  searchBox:SetText(text)
  searchBox:ClearFocus()
end
