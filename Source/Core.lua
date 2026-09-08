CobysCurrencySearcher = {
  Debug = {},
  Config = {},
  Utilities = {},
}

CobysCurrencySearcher.BRAND_COLOR = "F2C94C"

-------------------------------------------------------------------------------
-- EventBus event constants
-------------------------------------------------------------------------------
CobysCurrencySearcher.Events = {
  ConfigChanged = "cobys_currency_searcher_config_changed",
}

-------------------------------------------------------------------------------
-- Addon metadata
-------------------------------------------------------------------------------
local ADDON_NAME = "CobysCurrencySearcher"
local VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.0.0"

-------------------------------------------------------------------------------
-- Slash command registration and routing
-------------------------------------------------------------------------------
SLASH_COBYSCURRENCYSEARCHER1 = "/ccs"
SLASH_COBYSCURRENCYSEARCHER2 = "/cobyscurrencysearcher"

local function PrintHelp()
  local Msg = CobysCurrencySearcher.Utilities.Message
  Msg(CobySuite.Utilities.WrapColor("FFFFFF", "Coby's Currency Searcher v" .. VERSION) .. " slash commands:")
  Msg("  /ccs <text>: search the Currency tab for <text> (opens when you open the tab)")
  Msg("  /ccs settings: open the settings window")
  Msg("  /ccs debug: toggle the debug window")
  Msg("  /ccs version: print the addon version")
  Msg("  /ccs help: show this help")
end

local function HandleSlashCommand(input)
  input = strtrim(input or "")
  local cmd = strlower(input:match("^(%S+)") or "")

  if cmd == "" or cmd == "help" then
    PrintHelp()

  elseif cmd == "version" then
    CobysCurrencySearcher.Utilities.Message("v" .. VERSION)

  elseif cmd == "settings" or cmd == "config" or cmd == "show" then
    if CobysCurrencySearcher.Config.ToggleSettings then
      CobysCurrencySearcher.Config.ToggleSettings()
    end

  elseif cmd == "debug" then
    if CobysCurrencySearcherDebugWindow then
      CobysCurrencySearcherDebugWindow:SetShown(not CobysCurrencySearcherDebugWindow:IsShown())
    end

  else
    -- Anything else is a search query: open the Currency tab and search it.
    if CobysCurrencySearcher.Search and CobysCurrencySearcher.Search.OpenAndSearch then
      CobysCurrencySearcher.Search.OpenAndSearch(input)
    end
  end
end

SlashCmdList["COBYSCURRENCYSEARCHER"] = HandleSlashCommand

-------------------------------------------------------------------------------
-- Startup sequence
-------------------------------------------------------------------------------
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("ADDON_LOADED")
startupFrame:RegisterEvent("PLAYER_LOGIN")

startupFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    if CobysCurrencySearcher.Config.InitializeData then
      CobysCurrencySearcher.Config.InitializeData()
    end

    CobysCurrencySearcher.Debug.Log("INIT", "Coby's Currency Searcher v%s loaded", VERSION)

  elseif event == "PLAYER_LOGIN" then
    CobysCurrencySearcher.Debug.Log("INIT", "PLAYER_LOGIN complete")
  end
end)
