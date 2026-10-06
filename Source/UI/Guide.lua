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
local T = CobySuite_CobysCurrencySearcher.UI.GuideText

-- The house style (CobySuite.UI.GuideText): keys and commands in gold
-- (T.Key), this addon's own names for its parts (filters, settings pages
-- and controls, Go to Currency) in blue (T.Block), caveats in gray
-- (T.Note). The game's own terms (the Currency tab, Unused, Show on
-- Backpack, Transfer) stay plain.
local Key, Block, Note = T.Key, T.Block, T.Note

Guide.SECTIONS = {
    {
      key = "start", title = "Start here", icon = CobysCurrencySearcher.ICON,
      summary = "Open the Currency tab and type",
      body = {
        T.Bullets({
          "Open the character window and pick the Currency tab. The search box sits at the top, with a funnel and a gear beside it.",
          "Type a few letters to find matching currencies. Results keep their headers unless you choose " .. Block("Flat list") .. " in settings.",
          "Currencies inside collapsed headers are found too. Your headers stay exactly as you left them.",
          "Type a header's name, such as Midnight, to find currencies under it. Active filters still apply.",
          "While typing, press " .. Key("Escape") .. " to clear the search text, or click the clear button inside the search box. Filters stay on.",
        }),
        Note("Closing the Currency tab also clears the text unless ") .. Block("Remember my search while the window is closed") .. Note(" is on."),
      },
      try = { { "/ccs <text>", "Search the Currency tab straight from chat" } },
    },
    {
      key = "filters", title = "Filters", icon = "Interface\\Icons\\INV_Misc_Spyglass_03",
      summary = "The funnel narrows the list, with or without text",
      body = {
        T.Bullets({
          "Click the funnel beside the search box and tick what you want to see.",
          Block("Transferable") .. ": currencies that can move between your Warband's characters. " .. Block("Owned") .. ": only the ones you have.",
          Block("Capped") .. ": at their maximum or an earning limit, weekly included. " .. Block("Weekly") .. ": the ones with a weekly limit. " .. Block("On Backpack") .. ": the ones on your backpack bar.",
          "Currencies must match every selected filter. " .. Block("Owned") .. " and " .. Block("Transferable") .. " together show transferable currencies with a balance above zero.",
          "An x appears on the funnel while filters are active. Click it to clear all funnel filters. Search text stays.",
        }),
        Note("The game's filter dropdown also limits which currencies appear."),
      },
    },
    {
      key = "favorites", title = "Favorites", atlas = "auctionhouse-icon-favorite",
      summary = "Star the currencies you check most",
      body = {
        T.Bullets({
          "Click a currency's star to add or remove it from your favorites.",
          "If stars are hidden, search for a currency and move the mouse over its row.",
          "Stars are shared by all your characters and never change the order of the list.",
          "Tick " .. Block("Favorites") .. " in the funnel to see only your starred currencies.",
          "The " .. Block("Favorites") .. " settings page controls where stars appear: every row, search or filter results, or only the row under the mouse.",
          "The same page counts your favorites and can clear them all at once (it asks first).",
        }),
      },
    },
    {
      key = "results", title = "Clicking a result", icon = "Interface\\Icons\\INV_Misc_Coin_02",
      summary = "Currency options and transfers from search results",
      body = {
        T.Bullets({
          "Click a result for its currency options: Unused, Show on Backpack and, when available, Transfer.",
          "Transfer opens the game's transfer menu for that currency beside the window, and your search comes back.",
          "Tooltips, linking in chat and the backpack's modified click work as they do in the game's own list.",
          "In combat, Transfer clears your search text and filters. Find the currency in the game's list and click it there.",
        }),
        Note("If the transfer menu cannot open, the game's list stays visible and your search is cleared."),
      },
    },
    {
      key = "chat", title = "Chat and settings", icon = "Interface\\Icons\\INV_Misc_Gear_01",
      summary = "Search from chat, and make the box work your way",
      body = {
        T.Bullets({
          "Type " .. Key("/ccs <text>") .. " to search from anywhere. If the character window was last on another tab, a small window asks you to click " .. Block("Go to Currency") .. " first.",
          "After " .. Block("Go to Currency") .. ", " .. Key("/ccs <text>") .. " opens Currency directly until you switch tabs, log out or reload.",
          "Your Character key opens the window on the Character tab, so the next " .. Key("/ccs <text>") .. " asks again.",
          "The gear beside the funnel opens the settings, and so does " .. Key("/ccs settings") .. ".",
          Block("Results") .. ": a grouped or flat list, and whether descriptions are searched too. " .. Block("Search box") .. ": the cursor on open, what's remembered, and the search delay.",
          Block("Apply") .. " saves setting changes. " .. Block("Undo edits") .. " or closing the settings window discards unapplied changes. " .. Block("Defaults") .. " selects the default settings for you to Apply.",
        }),
        Note("Clear all favorites... takes effect after confirmation and does not wait for Apply."),
      },
      try = { { "/ccs settings", "Open the settings window" }, { "/ccs changelog", "See what changed in each version" } },
    },
}

local guide = CobySuite_CobysCurrencySearcher.UI.CreateGuideWindow({
  name = "CobysCurrencySearcherGuideWindow",
  title = U.WrapColor(CobysCurrencySearcher.BRAND_COLOR, "Coby's Currency Searcher") .. " Guide",
  icon = CobysCurrencySearcher.ICON,
  intro = "New here? Start with the first section. Click any heading to open or close it.",
  footer = "Open this guide any time with " .. U.WrapColor(U.Colors.HELP_COMMAND, "/ccs guide"),
  sections = Guide.SECTIONS,
  persist = { svTable = function() return COBYS_CURRENCY_SEARCHER_WINDOW_STATE end, key = "guideWindow" },
})

function Guide.Toggle() guide:Toggle() end

-- Shows the guide at its first section (a fresh install's first login)
function Guide.Show() guide:OpenSection(Guide.SECTIONS[1].key) end
