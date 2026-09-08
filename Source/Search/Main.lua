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
--   * Clicking a result selects that currency in Blizzard's own list, with
--     Blizzard's real options popup open, so Transfer works. The click lands
--     on an InsecureActionButtonTemplate child whose macro flips the
--     character window away and back (a secure rebuild) and /clicks a
--     delegate that our Update hook aims at the target's row; see "Secure
--     result click" below. Modified clicks (link, backpack toggle) and clicks
--     in combat are handled by our own code; in combat our replica popup
--     covers Unused and Show on Backpack, and its Transfer button hands off
--     to the list.
--
-- Blizzard only rebuilds its list from Update(); nothing on the frame listens
-- to CURRENCY_DISPLAY_UPDATE. We post-hook Update() only to refresh our own
-- results when their data changes, never to touch theirs.
-------------------------------------------------------------------------------

local Debug = CobysCurrencySearcher.Debug
local Config = CobysCurrencySearcher.Config
local Utilities = CobysCurrencySearcher.Utilities
local U = CobySuite.Utilities

local Search = {}
CobysCurrencySearcher.Search = Search

local DEBOUNCE_SECONDS = 0.2
local BOX_WIDTH = 150     -- spans from just right of the portrait to the filter dropdown
local BOX_GAP = 6         -- gap between the box and the filter dropdown
local MAX_LETTERS = 50

-- Blizzard's list geometry (TokenFrameMixin:OnLoad), mirrored exactly.
local LIST_PADDING = 10
local LIST_SPACING = 2

-- Blizzard's popup geometry (TokenFramePopup in Blizzard_TokenUI.xml).
local POPUP_WIDTH = 197
local POPUP_HEIGHT_DEFAULT = 100
local POPUP_HEIGHT_TRANSFER_ONLY = 90
local POPUP_HEIGHT_FULL = 135

-- Macro run on a secure path by a result row's click (see "Secure result
-- click"). Under the 255-character limit of 11.0.2 by a wide margin.
local RESULT_MACRO = "/click CharacterFrameTab1\n/click CharacterFrameTab3\n/click CobysCurrencySearcherClickStep"

local searchBox
local emptyLabel
local query = ""           -- normalized active query; "" when no search is active
local debounceTimer

local overlay              -- container covering Blizzard's ScrollBox + ScrollBar
local resultsBox           -- our WowScrollBoxList
local resultsBar           -- our MinimalScrollBar
local pendingSearch        -- /ccs text waiting for the tab to be opened by hand
local collapsedInResults = {}  -- header path key -> true, collapsed inside the results only
local lastResults          -- array of row tables currently shown

local popup                -- our replica of TokenFramePopup
local selectedCurrencyID   -- currency whose options popup is open (nil = none)
local blizzardListStale = false  -- our popup reordered the underlying list; see SetUnused

local clickStep            -- CobysCurrencySearcherClickStep, the /click delegate; created once
local macroInFlight = false  -- true from a result row's PreClick to its PostClick
local macroTarget          -- { currencyID, name, path, ancestors } for the click in flight
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
local function Matches(data, needle, matchDescriptions)
  local name = data.name
  if name and strfind(strlower(name), needle, 1, true) then
    return true
  end
  if matchDescriptions then
    local desc = data.description
    if desc and desc ~= "" and strfind(strlower(desc), needle, 1, true) then
      return true
    end
  end
  return false
end

local function MarkStackKept(stack, keep)
  for i = 1, #stack do
    keep[stack[i].data] = true
  end
end

-- Returns the subset of `rows` that matches `needle`, in list order, plus the
-- number of currency rows (non-headers) kept. Rows under a header the user
-- collapsed inside the results are left out.
local function BuildResults(rows, needle, matchDescriptions)
  local keep = {}
  local stack = {}   -- ancestry of the row being visited: { data, depth, force }
  local kept = 0

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
      if force then
        MarkStackKept(stack, keep)
      end
    else
      local force = #stack > 0 and stack[#stack].force
      if force or Matches(data, needle, matchDescriptions) then
        keep[data] = true
        kept = kept + 1
        MarkStackKept(stack, keep)
      end
    end
  end

  local results = {}
  local hiddenBelow   -- depth of the nearest results-collapsed header, or nil
  for _, data in ipairs(rows) do
    local depth = data.currencyListDepth or 0
    if hiddenBelow and depth <= hiddenBelow then
      hiddenBelow = nil
    end
    if keep[data] and not hiddenBelow then
      results[#results + 1] = data
      if data.isHeader and collapsedInResults[data.path] then
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

local function SetEmptyLabelShown(shown)
  if emptyLabel then
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
  if query == "" or not resultsBox then return end

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
  SetEmptyLabelShown(kept == 0)

  if popup and popup:IsShown() then
    local data = FindResult(selectedCurrencyID)
    if data then
      RefreshPopup(data)
    else
      popup:Hide()
    end
  end

  Debug.Log("SEARCH", "'%s': %d currencies, %d of %d rows shown (%d header(s) expanded for the snapshot)",
    query, kept, #results, #rows, expanded)
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

local function OnEntryClick(self)
  local data = self.elementData
  local linkedToChat = false
  if IsModifiedClick("CHATLINK") then
    linkedToChat = HandleModifiedItemClick(C_CurrencyInfo.GetCurrencyLink(data.currencyID))
  end
  if not linkedToChat then
    if IsModifiedClick("TOKENWATCHTOGGLE") then
      SetWatched(data, not data.isShowInBackpack)
    else
      TogglePopupFor(data)
    end
  end

  -- Hide this currency's tooltip if we're showing the options for it.
  if EntryIsSelected(self) then
    GameTooltip_Hide()
  else
    ShowEntryTooltip(self)
  end

  Refresh()
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

local OnResultPreClick, OnResultPostClick   -- defined under "Secure result click"

-- Initializers. The first acquisition of a pooled frame swaps the template's
-- TokenFrame-bound scripts for ours; every acquisition then runs Blizzard's
-- own Initialize so the visuals are theirs.
local function InitEntry(button, data)
  if not button.searcherReady then
    button.searcherReady = true
    button.IsSelected = EntryIsSelected
    button:SetScript("OnClick", OnEntryClick)
    button:SetScript("OnEnter", OnEntryEnter)
    button:SetScript("OnLeave", OnEntryLeave)
  end
  if not button.clicker and not InCombatLockdown() then
    -- Full-size insecure action button over the row. Its OnClick is
    -- Blizzard's secure action handler, so the row macro runs on a secure
    -- path (see "Secure result click"). Hover is forwarded to the row.
    -- Not created in combat; the row's own OnClick (replica popup) covers
    -- it until the next acquisition out of combat.
    local clicker = CreateFrame("Button", nil, button, "InsecureActionButtonTemplate")
    clicker:SetAllPoints()
    clicker:SetFrameLevel(button:GetFrameLevel() + 5)
    clicker:RegisterForClicks("LeftButtonUp")
    clicker:SetAttribute("useOnKeyDown", false)
    clicker:SetAttribute("type", "macro")
    clicker:SetAttribute("macrotext", RESULT_MACRO)
    -- Modified clicks never run the macro; PreClick handles them itself.
    clicker:SetAttribute("shift-type*", "")
    clicker:SetAttribute("ctrl-type*", "")
    clicker:SetAttribute("alt-type*", "")
    clicker:SetScript("PreClick", OnResultPreClick)
    clicker:SetScript("PostClick", OnResultPostClick)
    clicker:SetScript("OnEnter", function() OnEntryEnter(button) end)
    clicker:SetScript("OnLeave", function() OnEntryLeave(button) end)
    button.clicker = clicker
  end
  button:Initialize(data)
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

  resultsBox = CreateFrame("Frame", nil, overlay, "WowScrollBoxList")
  resultsBox:SetAllPoints(blizzBox)
  resultsBox:SetFrameLevel(overlay:GetFrameLevel() + 1)

  resultsBar = CreateFrame("EventFrame", nil, overlay, "MinimalScrollBar")
  resultsBar:SetAllPoints(blizzBar)
  resultsBar:SetFrameLevel(overlay:GetFrameLevel() + 1)

  local view = CreateScrollBoxListLinearView()
  view:SetElementIndentCalculator(function(elementData)
    local isTopLevelHeader = elementData.isHeader and elementData.currencyListDepth == 0
    if isTopLevelHeader then
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
end

-------------------------------------------------------------------------------
-- Options popup (replica of TokenFramePopup)
--
-- Unused and Show on Backpack work from here. Transfer cannot: it hands the
-- user back to Blizzard's clean list, which is the only place a transfer can
-- start (see the file header).
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

local TRANSFER_HANDOFF_TOOLTIP = "Opens the full list. Click the currency there to transfer. Out of combat, clicking a result selects it in the list with its options open instead."

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

local function OnTransferClick()
  local data = FindResult(selectedCurrencyID)
  popup:Hide()
  if not data then return end
  local where = (data.path and data.path ~= "") and (" under " .. data.path) or ""
  Utilities.Message(("To transfer %s, click it in the list%s."):format(data.name or "this currency", where))
  Debug.Log("SEARCH", "Transfer handoff for %s", data.name or "?")
  -- Clearing the box routes through SetQuery("") and hides the overlay, which
  -- brings Blizzard's untouched list back.
  SearchBoxTemplate_ClearText(searchBox)
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
  transfer:SetScript("OnClick", OnTransferClick)
  transfer:HookScript("OnEnter", function(self)
    if not self:IsEnabled() then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(TRANSFER_HANDOFF_TOOLTIP, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  transfer:HookScript("OnLeave", GameTooltip_Hide)
  f.TransferButton = transfer

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
    if resultsBox then
      resultsBox:ForEachFrame(function(frame)
        if frame.RefreshHighlightVisuals then frame:RefreshHighlightVisuals() end
      end)
    end
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
local function SetQuery(text)
  local newQuery = strlower(strtrim(text or ""))
  if newQuery == query then return end

  local wasEmpty = (query == "")
  query = newQuery

  if query == "" then
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

  if wasEmpty then
    Debug.State("SEARCH", "Search started")
    ShowOverlay()
  end
  if TokenFrame:IsShown() then
    Refresh()
    resultsBox:ScrollToBegin()
  end
end

local function CancelDebounce()
  if debounceTimer then
    debounceTimer:Cancel()
    debounceTimer = nil
  end
end

local function ScheduleApply(text)
  CancelDebounce()
  if strtrim(text or "") == "" then
    SetQuery("")
    return
  end
  debounceTimer = C_Timer.NewTimer(DEBOUNCE_SECONDS, function()
    debounceTimer = nil
    if searchBox then
      SetQuery(searchBox:GetText())
    end
  end)
end

-------------------------------------------------------------------------------
-- Secure result click
--
-- A result row's click lands on an InsecureActionButtonTemplate child whose
-- OnClick is Blizzard's SecureActionButton_OnClick, so RESULT_MACRO runs on
-- a secure path: it flips the character window away from and back to the
-- Currency tab (TokenFrame's own OnShow rebuilds the list with clean rows),
-- then /clicks CobysCurrencySearcherClickStep, a click-type action button that the
-- Update post-hook has aimed at the target's row between the macro lines.
-- Blizzard's own row OnClick then opens Blizzard's real popup with clean
-- data, and Transfer works from it. Verified in-game on 2026-09-08.
--
-- Before the macro, PreClick clears the search, records the user's collapse
-- state (restored when the tab hides) and folds every header except the
-- target's chain, so the rebuilt list has the target within its first
-- screen of rows. There is no secure way to scroll Blizzard's list, so a
-- target that still lands below the first screen is reported instead.
-------------------------------------------------------------------------------
local function ArmClickStep(row)
  if clickStep then
    clickStep:SetAttribute("clickbutton", row)
  end
end

local function PopupOpenFor(currencyID)
  if not (TokenFramePopup and TokenFramePopup:IsShown() and TokenFrame.selectedID) then
    return false
  end
  local info = C_CurrencyInfo.GetCurrencyListInfo(TokenFrame.selectedID)
  return info ~= nil and info.currencyID == currencyID
end

-- Clears the search at once. The box's OnTextChanged can arrive a frame
-- later; SetQuery("") is idempotent, so that is harmless.
local function ClearSearchNow()
  CancelDebounce()
  if searchBox and searchBox:GetText() ~= "" then
    searchBox:SetText("")
  end
  SetQuery("")
end

-- Runs before the secure action. Modified clicks and clicks in combat never
-- reach the macro (the modifier attributes are no-ops and the insecure
-- template refuses in combat), so they are handled here in full.
OnResultPreClick = function(clicker)
  local row = clicker:GetParent()
  local data = row.elementData
  if not data then return end
  if IsModifiedClick("CHATLINK") then
    HandleModifiedItemClick(C_CurrencyInfo.GetCurrencyLink(data.currencyID))
    return
  end
  if IsModifiedClick("TOKENWATCHTOGGLE") then
    SetWatched(data, not data.isShowInBackpack)
    Refresh()
    return
  end
  if IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown() then
    return   -- some other modified click; the macro is a no-op for it too
  end
  if InCombatLockdown() then
    -- The secure path is closed in combat; the replica popup covers Unused
    -- and Show on Backpack, and its Transfer button hands off to the list.
    TogglePopupFor(data)
    if EntryIsSelected(row) then GameTooltip_Hide() else ShowEntryTooltip(row) end
    Refresh()
    return
  end

  macroTarget = {
    currencyID = data.currencyID,
    name = data.name,
    path = data.path,
    ancestors = data.ancestors or {},
  }
  macroInFlight = true
  -- Remember the collapse state from before the first click so the tab's
  -- OnHide can put it back; later clicks keep the earliest record.
  if not restoreCollapsedKeys then
    restoreCollapsedKeys = {}
    for key in pairs(lastCollapsedKeys or {}) do
      restoreCollapsedKeys[key] = true
    end
  end
  ClearSearchNow()
  GameTooltip_Hide()
  CollapseAllExcept(macroTarget.ancestors)
  ArmClickStep(nil)
  Debug.State("SEARCH", "Result click: selecting %s in Blizzard's list", data.name or "?")
end

OnResultPostClick = function()
  if not macroInFlight then return end
  macroInFlight = false
  ArmClickStep(nil)
  local target = macroTarget
  macroTarget = nil
  if not target then return end
  if PopupOpenFor(target.currencyID) then
    Debug.Log("SEARCH", "%s selected; its options popup is open", target.name or "?")
    return
  end
  -- The rebuilt list did not put the row on screen (it sits below the first
  -- screen even with every other header folded). The list is left folded
  -- around it so it is a short scroll away.
  local where = (target.path and target.path ~= "") and (" under " .. target.path) or ""
  Utilities.Message(("%s is%s. Scroll down to it; the rest of the list is folded."):format(target.name or "That currency", where))
  Debug.Warn("SEARCH", "Result click: %s was not within the first screen after the rebuild", target.name or "?")
end

-- Post-hook on TokenFrame:Update(). Blizzard has just rebuilt its list from
-- fresh data. During a result click, aim the /click delegate at the target's
-- row (and disarm it once the popup is open); otherwise refresh our results
-- from the same data. Their frames are only ever read.
local function OnTokenFrameUpdated()
  blizzardListStale = false   -- any rebuild, theirs or ours, is fresh
  if macroInFlight and macroTarget then
    if PopupOpenFor(macroTarget.currencyID) then
      ArmClickStep(nil)
    else
      local id = macroTarget.currencyID
      local row = TokenFrame.ScrollBox:FindFrameByPredicate(function(frame, elementData)
        return elementData ~= nil and not elementData.isHeader and elementData.currencyID == id
      end)
      ArmClickStep(row)
    end
    return
  end
  if query == "" then return end
  ShowOverlay()   -- re-assert the fade; harmless when already applied
  Refresh()
end

-- Runs after Blizzard's own OnShow (and its clean Update). A search armed by
-- /ccs while the tab was closed starts here, so the tab is only ever
-- opened by the user's own action.
local function OnTokenFrameShown()
  if pendingSearch and searchBox then
    local text = pendingSearch
    pendingSearch = nil
    searchBox:SetText(text)
    searchBox:ClearFocus()
  end
end

local function OnTokenFrameHidden()
  if macroInFlight then return end   -- the tab detour of a result click
  CancelDebounce()
  if searchBox and searchBox:GetText() ~= "" then
    -- SetText("") fires OnTextChanged, which routes through SetQuery("").
    SearchBoxTemplate_ClearText(searchBox)
  elseif query ~= "" then
    SetQuery("")
  end
  RestoreCollapseState()
end

-------------------------------------------------------------------------------
-- Search box
--
-- Uses Blizzard's SearchBoxTemplate directly (magnifier icon, "Search"
-- instructions, built-in clear button) so it looks native inside the
-- Blizzard frame. CobySuite.UI.CreateTextInput is intentionally not used:
-- its commit wiring makes Escape revert to the last committed value, which
-- is wrong for a live filter.
-------------------------------------------------------------------------------
local function BuildSearchBox()
  local box = CreateFrame("EditBox", "CobysCurrencySearcherSearchBox", TokenFrame, "SearchBoxTemplate")
  box:SetSize(BOX_WIDTH, U.EditBoxHeight.SEARCH)
  -- One anchor: the vertical center comes from the dropdown and the left edge
  -- lands at x = 64, clear of the character portrait.
  box:SetPoint("RIGHT", TokenFrame.filterDropdown, "LEFT", -BOX_GAP, 0)
  box:SetAutoFocus(false)
  box:SetMaxLetters(MAX_LETTERS)
  -- The template reads self.instructionText in OnLoad, which is only set
  -- when the box comes from XML; set the placeholder ourselves.
  box.Instructions:SetText(SEARCH or "Search")

  box:SetScript("OnTextChanged", function(self)
    -- Keep the template's icon/clear-button behavior, then filter. This
    -- also runs for programmatic changes (clear button, OnHide), which is
    -- intended: an empty box must always mean "no search".
    SearchBoxTemplate_OnTextChanged(self)
    ScheduleApply(self:GetText())
  end)
  box:SetScript("OnEscapePressed", function(self)
    SearchBoxTemplate_ClearText(self)
  end)
  -- OnEnterPressed keeps the template's EditBox_ClearFocus.

  return box
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

  BuildOverlay()
  popup = BuildPopup()
  searchBox = BuildSearchBox()

  -- The /click delegate of RESULT_MACRO (see "Secure result click"). Created
  -- once: GetClickFrame caches the first object registered under a name.
  clickStep = CreateFrame("Button", "CobysCurrencySearcherClickStep", UIParent, "InsecureActionButtonTemplate")
  clickStep:SetSize(1, 1)
  clickStep:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  clickStep:SetAlpha(0)
  clickStep:RegisterForClicks("LeftButtonUp")
  clickStep:SetAttribute("useOnKeyDown", false)
  clickStep:SetAttribute("type", "click")

  -- Hook the frame instance: the mixin methods are copied onto the frame,
  -- and every internal call goes through TokenFrame:Update(). The hook only
  -- refreshes our results.
  hooksecurefunc(TokenFrame, "Update", OnTokenFrameUpdated)
  TokenFrame:HookScript("OnShow", OnTokenFrameShown)
  TokenFrame:HookScript("OnHide", OnTokenFrameHidden)

  CobysCurrencySearcher.EventBus:Register(Search, { CobysCurrencySearcher.Events.ConfigChanged })

  Debug.Log("INIT", "Search box and results list installed on the Currency tab")
end

-- Blizzard_TokenUI is not load-on-demand, but ContinueOnAddOnLoaded runs the
-- callback immediately when it is already loaded and waits otherwise, so it
-- is the safe way to sequence against it.
EventUtil.ContinueOnAddOnLoaded("Blizzard_TokenUI", Setup)

-------------------------------------------------------------------------------
-- EventBus
-------------------------------------------------------------------------------
function Search:ReceiveEvent(eventName, optionName)
  if eventName ~= CobysCurrencySearcher.Events.ConfigChanged then return end
  -- Re-filter when the description option flips during an active search.
  if (optionName == nil or optionName == Config.Options.MATCH_DESCRIPTIONS)
      and query ~= "" and TokenFrame:IsShown() then
    Refresh()
  end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

-- Searches for `text` on the Currency tab. If the tab is not open, the search
-- is armed and starts when the user opens it. The tab is never opened from
-- addon code: ToggleCharacter would run TokenFrame's OnShow and its Update
-- inside our execution, and rows built that way cannot start a warband
-- transfer (see the file header).
function Search.OpenAndSearch(text)
  if not searchBox then
    Debug.Warn("SEARCH", "/ccs refused: search box not installed")
    Utilities.Message("The Currency tab search box is not available.")
    return
  end
  text = strtrim(text or "")
  -- IsVisible, not IsShown: the tab can be shown inside a hidden character
  -- frame.
  if TokenFrame:IsVisible() then
    pendingSearch = nil
    searchBox:SetText(text)
    searchBox:ClearFocus()
    return
  end
  pendingSearch = text
  Utilities.Message(("Open the Currency tab to search for \"%s\"."):format(text))
  Debug.Log("SEARCH", "Armed /ccs search for '%s' until the Currency tab opens", text)
end
