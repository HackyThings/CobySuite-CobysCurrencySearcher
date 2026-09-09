---------------------------------------------------------------------------
-- CobySuite.UI.CreateWindow: the standard window shell
--
-- Every addon window in the suite is a BasicFrameTemplateWithInset frame
-- with the same trimmings: a solid dark background behind the inset art,
-- drag to move, an optional resize grip, a saved position (and size), an
-- Escape key that closes it, and a close button that also works in combat.
-- This builds that shell once so windows only add their content.
--
--   local f = CobySuite.UI.CreateWindow({
--     name          = "MyAddonOptionsWindow",  -- global name; needed for escapeCloses
--     title         = "My Addon Settings",     -- TitleText
--     width = 400, height = 190,
--     strata        = "HIGH",                  -- default HIGH
--     movable       = true,                    -- default true
--     resizable     = { minWidth = 600, minHeight = 400, maxWidth = 1200, maxHeight = 800 },  -- optional
--     solidBackground = true,                  -- default true (U.Colors.WINDOW_BG)
--     escapeCloses  = true,                    -- UISpecialFrames insert; default false
--     closeButtonInCombat = true,              -- close button calls Hide(); default true
--     persist = {                              -- optional saved position / size
--       svTable   = MY_ADDON_WINDOW_STATE,     -- table, or function returning it
--       key       = "options",
--       defaults  = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 },
--       fixedSize = true,                      -- ignore a saved size
--     },
--     point = { "CENTER", UIParent, "CENTER", 0, 80 },   -- initial anchor for a window without persist
--     mixin = MyWindowMixin,                   -- optional, applied before anything else
--     onDragStop = function(f) end,            -- optional, after the state is saved
--   })
--   f:SaveState()      f:RestoreState()      f:Toggle()
--
-- Escape: UISpecialFrames is the standard path (CloseSpecialWindows calls
-- Hide() directly, so it works in combat). The OnKeyDown +
-- SetPropagateKeyboardInput handler is deliberately not offered: it raises
-- ADDON_ACTION_BLOCKED on every keystroke while the window is open in
-- combat (ApexFury, 2026-04). UISpecialFrames itself is still on watch as a
-- possible taint vector, so it stays opt-in.
--
-- Close button: BasicFrameTemplate's default routes through HideUIPanel,
-- which silently no-ops in combat; the override is a plain Hide().
---------------------------------------------------------------------------
local UI = CobySuite.UI
local U = CobySuite.Utilities

local WindowMixin = {}

local function ResolveSV(persist)
  local sv = persist.svTable
  if type(sv) == "function" then sv = sv() end
  return sv
end

function WindowMixin:SaveState()
  local persist = self._persist
  if not persist then return end
  UI.SaveWindowState(self, ResolveSV(persist), persist.key)
end

function WindowMixin:RestoreState()
  local persist = self._persist
  if not persist then return end
  UI.RestoreWindowState(self, ResolveSV(persist), persist.key, persist.defaults)
  if persist.fixedSize then
    self:SetSize(self._width, self._height)
  end
end

function WindowMixin:Toggle()
  if self:IsShown() then
    self:Hide()
  else
    self:RestoreState()
    self:Show()
  end
end

function UI.CreateWindow(opts)
  opts = opts or {}
  local f = CreateFrame("Frame", opts.name, opts.parent or UIParent, opts.template or "BasicFrameTemplateWithInset")
  if opts.mixin then Mixin(f, opts.mixin) end
  Mixin(f, WindowMixin)

  f._width = opts.width or 400
  f._height = opts.height or 300
  f._persist = opts.persist
  f:SetSize(f._width, f._height)
  -- Initial anchor: opts.point (a SetPoint argument list) for a window that
  -- does not persist, otherwise the persist defaults, otherwise CENTER.
  if opts.point then
    f:SetPoint(unpack(opts.point))
  else
    local d = opts.persist and opts.persist.defaults or {}
    f:SetPoint(d.point or "CENTER", UIParent, d.relPoint or "CENTER", d.x or 0, d.y or 0)
  end
  f:SetFrameStrata(opts.strata or "HIGH")
  if opts.toplevel ~= false then f:SetToplevel(true) end
  if opts.clampToScreen ~= false then f:SetClampedToScreen(true) end
  f:EnableMouse(true)

  if opts.solidBackground ~= false then
    local solidBg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetAllPoints()
    local c = opts.backgroundColor or U.Colors.WINDOW_BG
    solidBg:SetColorTexture(c[1], c[2], c[3], c[4])
    f.SolidBackground = solidBg
  end

  if opts.title and f.TitleText then
    f.TitleText:SetText(opts.title)
  end

  if opts.movable ~= false then
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      self:SaveState()
      if opts.onDragStop then opts.onDragStop(self) end
    end)
  end

  if opts.resizable then
    local r = opts.resizable
    f:SetResizable(true)
    f:SetResizeBounds(r.minWidth or 200, r.minHeight or 150, r.maxWidth or 1600, r.maxHeight or 1000)
    f.ResizeGrip = UI.CreateResizeGrip(f)
    f.ResizeGrip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.ResizeGrip:SetScript("OnMouseUp", function()
      f:StopMovingOrSizing()
      f:SaveState()
      if opts.onResizeStop then opts.onResizeStop(f) end
    end)
  end

  if opts.escapeCloses then
    assert(opts.name, "CreateWindow: escapeCloses needs a global name")
    tinsert(UISpecialFrames, opts.name)
  end

  if opts.closeButtonInCombat ~= false and f.CloseButton then
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
  end

  if not opts.shown then f:Hide() end
  return f
end
