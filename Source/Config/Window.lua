-------------------------------------------------------------------------------
-- CobysCurrencySearcher Settings Window
--
-- A small form built with CobySuite.UI.CreateFormLayout. Changes apply the
-- moment a checkbox is clicked (no Stage/Apply), written through Config.Set.
-------------------------------------------------------------------------------

local Config = CobysCurrencySearcher.Config
local U = CobySuite.Utilities
local TC = U.Colors
local UI = CobySuite.UI

local WINDOW_W  = 400
local WINDOW_H  = 124
local PANEL_PAD = 16

local frame
local widgets = {}

-------------------------------------------------------------------------------
-- Window state persistence
-------------------------------------------------------------------------------
local function SaveState()
  UI.SaveWindowState(frame, COBYS_CURRENCY_SEARCHER_WINDOW_STATE, "options")
end

local function RestoreState()
  UI.RestoreWindowState(frame, COBYS_CURRENCY_SEARCHER_WINDOW_STATE, "options",
    { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 })
  -- Fixed layout: ignore any saved size.
  frame:SetSize(WINDOW_W, WINDOW_H)
end

local function Refresh()
  widgets.matchDescriptions:SetChecked(Config.Get(Config.Options.MATCH_DESCRIPTIONS))
end

-------------------------------------------------------------------------------
-- Frame construction
-------------------------------------------------------------------------------
local function BuildFrame()
  if frame then return frame end

  local f = CreateFrame("Frame", "CobysCurrencySearcherOptionsWindow", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(WINDOW_W, WINDOW_H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:Hide()

  local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  solidBg:SetAllPoints()
  local wbg = TC.WINDOW_BG
  solidBg:SetColorTexture(wbg[1], wbg[2], wbg[3], wbg[4])

  f.TitleText:SetText(U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " Settings")

  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveState()
  end)
  f:SetScript("OnShow", Refresh)

  -- Escape closes the window through UISpecialFrames: CloseSpecialWindows
  -- calls Hide() on each entry directly, so it works in combat. An OnKeyDown
  -- + SetPropagateKeyboardInput handler would raise ADDON_ACTION_BLOCKED on
  -- every keystroke while in combat.
  tinsert(UISpecialFrames, "CobysCurrencySearcherOptionsWindow")

  -- The template's close button routes through HideUIPanel, which no-ops in
  -- combat. A plain Hide() works regardless of combat state.
  if f.CloseButton then
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
  end

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 8, -28)
  content:SetSize(WINDOW_W - 16, WINDOW_H - 28 - 8)

  -- Label x, row height and start y are the builder defaults.
  local form = UI.CreateFormLayout(content, {
    width          = WINDOW_W - 16,
    dividerPadding = PANEL_PAD,
  })

  form:Section("Search")

  widgets.matchDescriptions = form:Checkbox{
    label        = "Match descriptions too",
    tooltip      = "Also match the search text against each currency's description, not only its name.",
    optionKey    = "MATCH_DESCRIPTIONS",
    initialValue = Config.Get(Config.Options.MATCH_DESCRIPTIONS),
    onChange     = function(v) Config.Set(Config.Options.MATCH_DESCRIPTIONS, v) end,
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
  BuildFrame()
  if frame:IsShown() then
    frame:Hide()
  else
    RestoreState()
    frame:Show()
  end
end
