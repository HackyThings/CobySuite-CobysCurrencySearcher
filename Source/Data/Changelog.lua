-------------------------------------------------------------------------------
-- Data.Changelog: the in-game changelog (UI/WhatsNew.lua, /ccs changelog),
-- one entry per version, newest first. Shown after an update with every
-- version newer than the one the player last ran opened.
--
-- An entry: version (the TOC's), title (a few words), date ("2026-10-02"
-- once released; nil shows "Beta"), and the lists new, changed and fixed,
-- each a line a player reads (the CHANGELOG.md style: what changed for
-- them, no internals), short enough to fit on one line: "Feature: what it
-- does", the part before the first ": " shown in blue, and {/ccs} for a
-- command in gold. Keep it in step with CHANGELOG.md: /release adds the
-- entry.
-------------------------------------------------------------------------------
CobysCurrencySearcher.Data = CobysCurrencySearcher.Data or {}

CobysCurrencySearcher.Data.Changelog = {
  {
    version = "1.0.5",
    title = "New settings look",
    date = "2026-10-01",
    new = {
      "Minimap addon list: click the addon to open its settings",
      "Clear all favorites: a button on the Favorites page",
    },
    changed = {
      "Settings: Results, Favorites and Search box pages with picture tiles",
      "Go to Currency: larger text; {/ccs} then opens straight to Currency",
    },
    fixed = {
      "Go to Currency: the search is kept after a login or reload",
      "Transfer: clicking with two modifier keys held does nothing",
    },
  },
  {
    version = "1.0.4",
    title = "Guide and What's New",
    date = "2026-10-01",
    new = {
      "Guide: searching, filters and favorites, {/ccs guide}",
      "What's New: {/ccs changelog}, and after each update",
      "Options > AddOns: a page with an Open Settings button",
    },
    changed = {
      "Commands: {/ccs} opens the settings, {/ccs help} lists the rest",
      "Command words: guide, changelog and options no longer search",
      "Settings: the addon's icon in the title",
    },
    fixed = {
      "Settings window: resizing stops at the screen edge",
    },
  },
  {
    version = "1.0.3",
    title = "Windows that behave",
    date = "2026-09-29",
    changed = {
      "Windows: click any window to bring it to the front",
      "Settings: drag the corner to resize; the size is kept",
      "Settings: groups sit closer together",
      "Command list: {/ccs help} is easier to read",
      "Search from chat: asks for one click when on another tab",
      "Search from chat in combat: waits until combat ends",
    },
  },
  {
    version = "1.0.2",
    title = "New settings window",
    date = "2026-09-21",
    changed = {
      "Settings: Search, Favorites and Filters on the left",
      "Apply, Cancel and Defaults: nothing changes until you Apply",
      "Settings: open in combat, even the first time",
      "Debug log: Escape closes it",
      "Command list: {/ccs help} in color",
    },
    fixed = {
      "Show on Backpack: the game's list underneath updates at once",
      "A damaged setting goes back to its default at login",
      "Works beside other Coby addons of any version",
    },
  },
  {
    version = "1.0.1",
    title = "Favorites and filters",
    date = "2026-09-09",
    new = {
      "Favorites: click the star on any currency row",
      "Filters: Transferable, Owned, Capped, Weekly, On Backpack",
      "Settings gear: beside the funnel on the Currency tab",
      "Filters persist between logins: an option, off at first",
      "More settings: focus, keep text, delay, flat results, star",
    },
    changed = {
      "Results: a click opens its options right in the results",
      "Transfer: opens beside the window, and the search stays",
      "Search from chat: {/ccs} opens the tab and searches",
    },
    fixed = {
      "Match descriptions too: now works",
    },
  },
  {
    version = "1.0.0",
    title = "First release",
    date = "2026-09-08",
    new = {
      "Search box: on the Currency tab, results as you type",
      "No gaps: only matching rows, in the game's own style",
      "Collapsed headers: searched without opening them",
      "Header names: type one to see its whole group",
      "Result rows: tooltips, linking and the backpack click",
      "Match descriptions too: an option to search descriptions",
      "Search from chat: {/ccs} and your text",
    },
  },
}
