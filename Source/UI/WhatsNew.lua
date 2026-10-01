-------------------------------------------------------------------------------
-- WhatsNew: the changelog window and what its login shows, on the shared
-- CobySuite.UI.CreateWhatsNewWindow (the suite's standard, as Recollect's):
-- one collapsible section per version of Data/Changelog.lua, /ccs changelog
-- any time. At login COBYS_CURRENCY_SEARCHER_WINDOW_STATE.lastVersion says
-- what the player last ran: none on a fresh install opens the feature
-- guide, none on an install from before this window (existingInstall,
-- settings already saved) records the version and opens nothing, an older
-- version opens this window with every version since then open, else
-- nothing; a window waits for combat to end. Core.lua's PLAYER_LOGIN calls
-- OnLogin.
-------------------------------------------------------------------------------
local U = CobySuite_CobysCurrencySearcher.Utilities

local WhatsNew = {}
CobysCurrencySearcher.WhatsNew = WhatsNew

local changelog = CobySuite_CobysCurrencySearcher.UI.CreateWhatsNewWindow({
  name = "CobysCurrencySearcherChangelogWindow",
  title = "Coby's Currency Searcher: What's New",
  icon = CobysCurrencySearcher.ICON,
  intro = "What changed in each version of Coby's Currency Searcher, newest first. Click a version to open or close it.",
  footer = "Open this window any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ccs changelog"),
  entries = CobysCurrencySearcher.Data.Changelog,
  version = CobysCurrencySearcher.VERSION,
  state = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end,
  onFirstRun = function() if CobysCurrencySearcher.Guide then CobysCurrencySearcher.Guide.Show() end end,
  existingInstall = function() return CobysCurrencySearcher.hadSavedConfig == true end,
  combatMessage = function(text) CobysCurrencySearcher.Utilities.Message(text) end,
  onShow = function(what) CobysCurrencySearcher.Debug.Log("UI", "Login shows the %s", what) end,
})

function WhatsNew.Toggle() changelog:Toggle() end
function WhatsNew.OnLogin() changelog:OnLogin() end
