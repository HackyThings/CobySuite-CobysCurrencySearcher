-------------------------------------------------------------------------------
-- Guide: the feature guide behind the settings window's Guide button and
-- /ccs guide (a new player's first session: start here, then filters,
-- favorites, what a result's click does, and last chat and settings). A
-- fresh install opens it at its first section (UI/WhatsNew.lua). The
-- suite's standard guide, as Recollect's. There is no "?" on the Currency
-- tab: that tab is Blizzard's, and the addon adds nothing to it beyond the
-- search row and a favorite star on each currency row (a child button;
-- the rows' own data stays untouched by addon code, or their transfer
-- clicks are blocked). Built at load, so opening it in combat creates
-- nothing. Keep the text in step with the README.
-------------------------------------------------------------------------------
local Guide = {}
CobysCurrencySearcher.Guide = Guide

local U = CobySuite_CobysCurrencySearcher.Utilities

Guide.SECTIONS = {
    {
      key = "start", title = "Start here", icon = CobysCurrencySearcher.ICON,
      summary = "Open the Currency tab and type",
      body = {
        "- Open the character window and pick the |cFFFFD100Currency|r tab. The search box sits at the top, with a funnel and a gear beside it.",
        "- Type a few letters. Only the matching currencies show, under their headers, with no empty rows.",
        "- Currencies inside collapsed headers are found too. Your headers stay exactly as you left them.",
        "- Type a header's name, such as Midnight, to see everything under it.",
        "- Escape, the clear button or closing the window empties the box (a setting can keep your text).",
      },
      try = { { "/ccs <text>", "Search the Currency tab straight from chat" } },
    },
    {
      key = "filters", title = "Filters", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      summary = "The funnel narrows the list, with or without text",
      body = {
        "- Click the funnel beside the search box and tick what you want to see.",
        "- |cFFFFD100Transferable|r: currencies that can move between your Warband's characters. |cFFFFD100Owned|r: only the ones you have.",
        "- |cFFFFD100Capped|r: at their maximum or this week's cap. |cFFFFD100Weekly|r: the ones with a weekly limit. |cFFFFD100On Backpack|r: the ones on your backpack bar.",
        "- Ticks add up: Owned and Transferable together show the transferable currencies this character holds.",
        "- A red x on the funnel means a filter is on. Click it to clear them all.",
      },
    },
    {
      key = "favorites", title = "Favorites", atlas = "auctionhouse-icon-favorite",
      summary = "Star the currencies you check most",
      body = {
        "- Every currency row starts with a star. Click it to mark that currency.",
        "- Stars are shared by all your characters and never change the order of the list.",
        "- Tick |cFFFFD100Favorites|r in the funnel to see only your starred currencies.",
        "- Too many stars on screen? The settings can show them on search results only, or only under the mouse.",
      },
    },
    {
      key = "results", title = "Clicking a result", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      summary = "Unused, Show on Backpack and Transfer, without losing the search",
      body = {
        "- Click a result to open its options right there: |cFFFFD100Unused|r, |cFFFFD100Show on Backpack|r and |cFFFFD100Transfer|r.",
        "- Transfer opens the game's transfer menu for that currency beside the window, and your search stays put.",
        "- Tooltips, linking in chat and the backpack's modified click work as they do in the game's own list.",
        "- In combat, Transfer clears the search instead, so you can pick the currency in the game's list yourself.",
      },
    },
    {
      key = "chat", title = "Chat and settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      summary = "Search from chat, and make the box work your way",
      body = {
        "- Type |cFFFFD100/ccs|r and a name to search from anywhere. If the character window was last on another tab, a small window asks you to click |cFFFFD100Go to Currency|r first.",
        "- The gear beside the funnel opens the settings, and so does /ccs settings.",
        "- Settings include matching descriptions too, focusing the box when the tab opens, keeping your text, flat results and the search delay.",
        "- Changes wait for |cFFFFD100Apply|r. Cancel or closing the window throws them away.",
      },
      try = { { "/ccs settings", "Open the settings window" }, { "/ccs changelog", "See what changed in each version" } },
    },
}

local guide = CobySuite_CobysCurrencySearcher.UI.CreateGuideWindow({
  name = "CobysCurrencySearcherGuideWindow",
  title = "Coby's Currency Searcher Guide",
  icon = CobysCurrencySearcher.ICON,
  intro = "New here? Start with the first section. Click any heading to open or close it.",
  footer = "Open this guide any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ccs guide"),
  sections = Guide.SECTIONS,
  persist = { svTable = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end, key = "guideWindow" },
})

function Guide.Toggle() guide:Toggle() end

-- Shows the guide at its first section (a fresh install's first login)
function Guide.Show() guide:OpenSection(Guide.SECTIONS[1].key) end
