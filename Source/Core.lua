CobysCurrencySearcher = {
  Debug = {},
  Config = {},
  Utilities = {},
  Data = {},
}

CobysCurrencySearcher.BRAND_COLOR = "F2C94C"
CobysCurrencySearcher.ICON = "Interface\\Icons\\INV_Misc_Coin_01"   -- the TOC's IconTexture
-- the group name after a flat result's name (the results and the settings' example)
CobysCurrencySearcher.FLAT_GROUP_COLOR = CobySuite_CobysCurrencySearcher.Utilities.ColorToHex(CobySuite_CobysCurrencySearcher.Utilities.Colors.DISABLED_GRAY)

-------------------------------------------------------------------------------
-- EventBus event constants
-------------------------------------------------------------------------------
CobysCurrencySearcher.Events = {
  ConfigChanged = "cobys_currency_searcher_config_changed",
  -- payload: the currency starred or unstarred, nil when every star changed
  FavoritesChanged = "cobys_currency_searcher_favorites_changed",
}

-------------------------------------------------------------------------------
-- Addon metadata
-------------------------------------------------------------------------------
local ADDON_NAME = "CobysCurrencySearcher"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0.0"
CobysCurrencySearcher.VERSION = VERSION

-------------------------------------------------------------------------------
-- Slash commands
--
-- Registered through CobySuite.Slash, which generates help and version, with
-- the suite's standard commands (settings, guide, changelog, debug, test).
-- The addon has no main window, so there is no show command and a bare /ccs
-- opens settings (the suite's standard). Anything that is not a command is a search query
-- (fallback). Everything else loads after Core.lua, so each command
-- resolves its module per call.
-------------------------------------------------------------------------------
local function ToggleSettings()
  if CobysCurrencySearcher.Config.ToggleSettings then
    CobysCurrencySearcher.Config.ToggleSettings()
  end
end

local commands = CobySuite_CobysCurrencySearcher.Slash.StandardCommands({
  settings = ToggleSettings,
  guide = function() if CobysCurrencySearcher.Guide then CobysCurrencySearcher.Guide.Toggle() end end,
  changelog = function() if CobysCurrencySearcher.WhatsNew then CobysCurrencySearcher.WhatsNew.Toggle() end end,
  debug = function()
    if CobysCurrencySearcher.DebugWindow then CobysCurrencySearcher.DebugWindow:Toggle() end
  end,
  -- Development only: the suites are stripped from release builds, and the
  -- test command's available() hides it from help there, so "/ccs test" is
  -- a search again in a release
  tests = function() return CobysCurrencySearcher.Tests end,
  extra = {
    { usage = "<text>", help = "Open the Currency tab and search for <text>" },
  },
})

-- "/ccs show" has opened the settings since 1.0.0, so it stays an alias
-- there (hidden from help like every alias) rather than a search for "show"
for _, def in ipairs(commands) do
  if def.name == "settings" then
    def.aliases[#def.aliases + 1] = "show"
  end
end

CobySuite_CobysCurrencySearcher.Slash.Register({
  key = "COBYSCURRENCYSEARCHER",
  slashes = { "/ccs", "/cobyscurrencysearcher" },
  title = "Coby's Currency Searcher",
  version = VERSION,
  message = function(text) CobysCurrencySearcher.Utilities.Message(text) end,
  onEmpty = ToggleSettings,
  commands = commands,
  fallback = function(input)
    -- Anything else is a search query: open the Currency tab and search it.
    if CobysCurrencySearcher.Search and CobysCurrencySearcher.Search.OpenAndSearch then
      CobysCurrencySearcher.Search.OpenAndSearch(input)
    end
  end,
})

-------------------------------------------------------------------------------
-- Addon compartment (the addon list on the minimap): the shared launcher's
-- compartment half only, no minimap button and no LibDataBroker object. A
-- click opens the settings, as /ccs alone does (the addon has no window of
-- its own, and opening the Currency tab takes the player's own click on Go
-- to Currency). The global functions named in the TOC route to it.
-------------------------------------------------------------------------------
local launcher = CobySuite_CobysCurrencySearcher.UI.CreateLauncher({
  name = ADDON_NAME,
  minimapButton = false,
  broker = false,
  onLeftClick = ToggleSettings,
  onRightClick = ToggleSettings,
  compartmentTooltipAnchor = "ANCHOR_LEFT",
  tooltip = function()
    return CobySuite_CobysCurrencySearcher.UI.LauncherTooltip({
      title = "Coby's Currency Searcher", brandColor = CobysCurrencySearcher.BRAND_COLOR,
      icon = CobysCurrencySearcher.ICON, leftClick = "Open settings",
    })
  end,
})
CobysCurrencySearcher.Launcher = launcher

function CobysCurrencySearcher_OnAddonCompartmentClick(_, button) launcher:OnCompartmentClick(button) end
function CobysCurrencySearcher_OnAddonCompartmentEnter(_, menuItem) launcher:OnCompartmentEnter(menuItem) end
function CobysCurrencySearcher_OnAddonCompartmentLeave() launcher:OnCompartmentLeave() end

-------------------------------------------------------------------------------
-- Startup sequence
-------------------------------------------------------------------------------
EventUtil.ContinueOnAddOnLoaded(ADDON_NAME, function()
  -- Settings saved before this login mean a player of an earlier release:
  -- What's New records the version instead of opening the new-player guide
  CobysCurrencySearcher.hadSavedConfig = type(COBYS_CURRENCY_SEARCHER_CONFIG) == "table"
    and next(COBYS_CURRENCY_SEARCHER_CONFIG) ~= nil
  if CobysCurrencySearcher.Config.InitializeData then
    CobysCurrencySearcher.Config.InitializeData()
  end
  CobysCurrencySearcher.Debug.Log("INIT", "Coby's Currency Searcher v%s loaded", VERSION)
end)

EventUtil.RegisterOnceFrameEventAndCallback("PLAYER_LOGIN", function()
  -- A fresh install opens the guide; an update, the changelog
  if CobysCurrencySearcher.WhatsNew then CobysCurrencySearcher.WhatsNew.OnLogin() end
  CobysCurrencySearcher.Debug.Log("INIT", "PLAYER_LOGIN complete")
end)
