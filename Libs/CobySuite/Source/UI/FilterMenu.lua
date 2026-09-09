---------------------------------------------------------------------------
-- CobySuite.UI.CreateFilterButton: funnel icon + checkbox filter menu
--
-- A compact "narrow the list" control for the space beside a search box:
-- the objective tracker's funnel icon (ObjectiveTrackerContainerFilterButtonTemplate,
-- 18x19) opens a small menu of checkbox rows drawn with the atlases of
-- Blizzard's MenuStyle1, so it matches a Blizzard dropdown beside it. While
-- any filter is on the funnel carries Blizzard's red reset x, which clears
-- them all. The menu closes on a click anywhere outside it.
--
-- Blizzard's Menu system (DropdownButton:SetupMenu, MenuUtil) is
-- deliberately not used: its pooled menu frames are shared with every menu
-- on screen, including ones whose buttons reach protected calls, and a
-- pooled frame first created from addon code could carry taint into them.
-- This menu is only ever touched by its owner. UI.BuildCheckboxMenu is the
-- Blizzard-Menu sibling for places where that concern does not apply.
--
--   local funnel = CobySuite.UI.CreateFilterButton(parent, {
--     name  = "MyAddonFilterButton",          -- optional
--     point = { "RIGHT", anchor, "LEFT", -6, 0 },
--     defs  = {                                -- menu rows, in order
--       { key = "owned", label = "Owned", tooltip = "Only what you have." },
--     },
--     isChecked  = function(key) return filters[key] == true end,
--     setChecked = function(key, on) ... end,  -- apply the change
--     onClear    = function() ... end,         -- the reset x
--     tooltipTitle = FILTER,                   -- default FILTER
--     tooltipIdle  = "Narrow the list.",       -- shown when nothing is on
--     menu = { name = "MyAddonFilterMenu", parent = parent, strata = "DIALOG" },
--   })
--   funnel:Refresh()        -- after filters change elsewhere
--   funnel.Menu             -- the menu frame; funnel.Menu.rows[i].key
--   funnel.ResetButton
---------------------------------------------------------------------------
local UI = CobySuite.UI

local BUTTON_WIDTH = 18
local BUTTON_HEIGHT = 19
local BUTTON_ATLAS = {
  normal = "ui-questtrackerbutton-filter",
  pressed = "ui-questtrackerbutton-filter-pressed",
  highlight = "ui-questtrackerbutton-red-highlight",
}
local RESET_SIZE = 12   -- UIResetButtonTemplate is 23px; scaled down to sit on the badge's corner
local RESET_OFFSET = 3  -- past the badge's top-right edge, so the x overlaps the frame, not the glyph
local MENU_BG_ATLAS = "common-dropdown-bg"
local MENU_BG_ALPHA = 0.925
local MENU_ROW_HOVER_ATLAS = "common-dropdown-customize-mouseover"
local MENU_ROW_HOVER_ALPHA = 0.15   -- MenuTemplates.lua sets HighlightBGTex to this on hover
local MENU_BOX_ATLAS = "common-dropdown-ticksquare"
local MENU_CHECK_ATLAS = "common-dropdown-icon-checkmark-yellow"
local MENU_INSET = { left = 8, top = 8, right = 8, bottom = 15 }   -- MenuStyle1
local MENU_EXTRA_WIDTH = 20        -- MenuStyle1's child extent padding
local MENU_MIN_CONTENT_WIDTH = 80
local MENU_ROW_HEIGHT = 20
local MENU_OFFSET = { x = 6, y = 2 }   -- as Blizzard's filter dropdowns place their menu

---------------------------------------------------------------------------
-- CreateFilterStyleButton: the funnel's badge with another glyph on it
--
-- Blizzard ships the red badge only with its funnel, collapse and expand
-- glyphs. For a sibling button (a settings gear beside the funnel) the
-- badge is the funnel atlas itself: a patch sampled from a plain part of
-- the badge's interior covers the funnel glyph, and the caller's glyph
-- atlas is drawn on top, tinted the funnel's gold. Every pixel of the frame
-- and its shading is Blizzard's, so the pair matches exactly.
--
--   local gear = CobySuite.UI.CreateFilterStyleButton(parent, {
--     name = "MyAddonSettingsButton", point = { ... },
--     glyphAtlas = "GM-icon-settings", glyphInset = -1,   -- negative grows a padded glyph
--     glyphTint = { 1, 0.82, 0.1 },
--     tooltip = "Settings", onClick = function() ... end,
--   })
---------------------------------------------------------------------------
local GLYPH_TINT = { 1, 0.82, 0.1 }
local GLYPH_PUSHED_SHADE = 0.75
local BADGE_PATCH_INSET = 3                          -- keeps the badge's rounded frame
local BADGE_PATCH_SAMPLE = { 0.12, 0.22, 0.55, 0.70 } -- plain interior: left of the funnel's stem (u1, u2, v1, v2)

local function CoverGlyph(button, atlasName)
  local info = C_Texture.GetAtlasInfo(atlasName)
  if not info then return nil end
  local patch = button:CreateTexture(nil, "OVERLAY", nil, 0)
  patch:SetTexture(info.file)
  local l, r = info.leftTexCoord, info.rightTexCoord
  local t, b = info.topTexCoord, info.bottomTexCoord
  local s = BADGE_PATCH_SAMPLE
  patch:SetTexCoord(l + (r - l) * s[1], l + (r - l) * s[2], t + (b - t) * s[3], t + (b - t) * s[4])
  patch:SetPoint("TOPLEFT", BADGE_PATCH_INSET, -BADGE_PATCH_INSET)
  patch:SetPoint("BOTTOMRIGHT", -BADGE_PATCH_INSET, BADGE_PATCH_INSET)
  return patch
end

function UI.CreateFilterStyleButton(parent, opts)
  assert(opts and opts.glyphAtlas, "CreateFilterStyleButton needs glyphAtlas")
  local button = CreateFrame("Button", opts.name, parent)
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  if opts.point then button:SetPoint(unpack(opts.point)) end
  button:SetNormalAtlas(BUTTON_ATLAS.normal)
  button:SetPushedAtlas(BUTTON_ATLAS.pressed)
  button:SetHighlightAtlas(BUTTON_ATLAS.highlight, "ADD")

  button.Patch = CoverGlyph(button, BUTTON_ATLAS.normal)

  local inset = opts.glyphInset or 0
  local glyph = button:CreateTexture(nil, "OVERLAY", nil, 1)
  glyph:SetAtlas(opts.glyphAtlas)
  glyph:SetPoint("TOPLEFT", inset, -inset)
  glyph:SetPoint("BOTTOMRIGHT", -inset, inset)
  local tint = opts.glyphTint or GLYPH_TINT
  glyph:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
  button.Glyph = glyph

  -- Pressed: the badge swaps to its pressed art; the glyph darkens with it.
  button:SetScript("OnMouseDown", function()
    local s = GLYPH_PUSHED_SHADE
    glyph:SetVertexColor(tint[1] * s, tint[2] * s, tint[3] * s, tint[4] or 1)
  end)
  button:SetScript("OnMouseUp", function()
    glyph:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
  end)

  if opts.onClick then button:SetScript("OnClick", opts.onClick) end
  if opts.tooltip then UI.AddTooltip(button, opts.tooltip, opts.tooltipAnchor or "ANCHOR_RIGHT") end
  return button
end

local function BuildMenu(button, opts)
  local menuOpts = opts.menu or {}
  local menu = CreateFrame("Frame", menuOpts.name, menuOpts.parent or button:GetParent())
  menu:SetFrameStrata(menuOpts.strata or "DIALOG")
  menu:EnableMouse(true)
  menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", MENU_OFFSET.x, MENU_OFFSET.y)
  menu:Hide()

  -- MenuStyle1: the art runs 10px past the sides and 3px past top and bottom.
  local bg = menu:CreateTexture(nil, "BACKGROUND")
  bg:SetAtlas(MENU_BG_ATLAS)
  bg:SetPoint("TOPLEFT", -10, 3)
  bg:SetPoint("BOTTOMRIGHT", 10, -3)
  bg:SetAlpha(MENU_BG_ALPHA)

  local function OnRowClick(row)
    local on = not opts.isChecked(row.key)
    PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    opts.setChecked(row.key, on)
    button:Refresh()
  end

  local inset = MENU_INSET
  local contentWidth = MENU_MIN_CONTENT_WIDTH
  menu.rows = {}
  for i, def in ipairs(opts.defs) do
    local row = CreateFrame("Button", nil, menu)
    row.key = def.key
    row:SetHeight(MENU_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", inset.left, -(inset.top + (i - 1) * MENU_ROW_HEIGHT))
    row:SetPoint("RIGHT", -inset.right, 0)

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAtlas(MENU_ROW_HOVER_ATLAS)
    hover:SetAllPoints()
    hover:SetAlpha(MENU_ROW_HOVER_ALPHA)

    -- MenuVariants.CreateCheckbox geometry.
    local box = row:CreateTexture(nil, "ARTWORK")
    box:SetAtlas(MENU_BOX_ATLAS, true)
    box:SetPoint("LEFT")
    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetAtlas(MENU_CHECK_ATLAS, true)
    check:SetPoint("CENTER", box, "CENTER", 2, 1)
    check:Hide()
    row.Check = check

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 7, 1)
    text:SetHeight(MENU_ROW_HEIGHT)
    text:SetText(def.label)
    row.Text = text

    row:SetScript("OnClick", OnRowClick)
    if def.tooltip then
      UI.AddTooltip(row, def.tooltip, "ANCHOR_RIGHT")
    end
    contentWidth = math.max(contentWidth, box:GetWidth() + 7 + text:GetStringWidth())
    menu.rows[i] = row
  end
  menu:SetSize(inset.left + contentWidth + MENU_EXTRA_WIDTH + inset.right,
    inset.top + #opts.defs * MENU_ROW_HEIGHT + inset.bottom)

  -- The button's "open" look follows the menu.
  menu:SetScript("OnHide", function() button:Refresh() end)
  UI.HideOnClickOutside(menu, { owners = { button } })
  return menu
end

function UI.CreateFilterButton(parent, opts)
  assert(opts and opts.defs and opts.isChecked and opts.setChecked, "CreateFilterButton needs defs, isChecked and setChecked")
  local button = CreateFrame("Button", opts.name, parent)
  button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
  if opts.point then button:SetPoint(unpack(opts.point)) end
  -- Same three textures as the objective tracker's filter button.
  button:SetNormalAtlas(BUTTON_ATLAS.normal)
  button:SetPushedAtlas(BUTTON_ATLAS.pressed)
  button:SetHighlightAtlas(BUTTON_ATLAS.highlight, "ADD")

  local function AnyChecked()
    for _, def in ipairs(opts.defs) do
      if opts.isChecked(def.key) then return true end
    end
    return false
  end

  -- Blizzard's reset x (UIResetButtonTemplate), scaled down to sit inside
  -- the badge's top-right corner.
  local reset = CreateFrame("Button", nil, button, "UIResetButtonTemplate")
  reset:SetSize(RESET_SIZE, RESET_SIZE)
  reset:SetPoint("TOPRIGHT", button, "TOPRIGHT", RESET_OFFSET, RESET_OFFSET)
  reset:SetFrameLevel(button:GetFrameLevel() + 2)
  reset:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    if opts.onClear then opts.onClear() end
    button:Refresh()
  end)
  UI.AddTooltip(reset, opts.clearTooltip or "Clear filters", "ANCHOR_RIGHT")
  button.ResetButton = reset

  function button:Refresh()
    local open = self.Menu ~= nil and self.Menu:IsShown()
    self:SetNormalAtlas(open and BUTTON_ATLAS.pressed or BUTTON_ATLAS.normal)
    self.ResetButton:SetShown(AnyChecked())
    if self.Menu then
      for _, row in ipairs(self.Menu.rows) do
        row.Check:SetShown(opts.isChecked(row.key) == true)
      end
    end
  end

  function button:ToggleMenu()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    self.Menu:SetShown(not self.Menu:IsShown())
    self:Refresh()
  end

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, opts.tooltipTitle or FILTER or "Filter")
    local active = {}
    for _, def in ipairs(opts.defs) do
      if opts.isChecked(def.key) then
        active[#active + 1] = def.label
      end
    end
    if #active > 0 then
      GameTooltip_AddNormalLine(GameTooltip, "On: " .. table.concat(active, ", "))
    elseif opts.tooltipIdle then
      GameTooltip_AddNormalLine(GameTooltip, opts.tooltipIdle)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:SetScript("OnClick", function(self) self:ToggleMenu() end)

  button.Menu = BuildMenu(button, opts)
  button:Refresh()
  return button
end
