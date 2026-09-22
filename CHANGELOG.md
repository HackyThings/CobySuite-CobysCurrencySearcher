# Changelog

All notable changes to Coby's Currency Searcher are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] - 2026-09-21

### Changed

- Redesigned settings window, with Search, Favorites and Filters as categories on the left.
- Changes take effect when you press Apply. Cancel, or closing the window, throws them away. The Defaults button fills in every default for you to check, and nothing changes until you press Apply. It never unticks your filters.
- The settings window opens in combat, even the first time.
- Escape closes the debug log window.
- `/ccs help` is in color: the command, what you fill in and its description each stand out.

### Fixed

- Show on Backpack from a search, with the popup's checkbox or Shift-click on a result, now updates Blizzard's own list underneath in the same click. After you clear the search, the next Shift-click on that currency in Blizzard's list reverses the check instead of repeating it, and with a full backpack bar the "too many" error no longer comes back on every click. You hear the character tab sound when this happens, and an open transfer menu closes. In combat the currency still goes on or off your backpack bar, but Blizzard's list underneath only gets its check mark updated, as before, until Blizzard's list next refreshes.
- A damaged saved setting goes back to its default at login instead of causing errors.
- Works correctly beside other Coby addons of different versions: each addon now carries its own private copy of the shared code, so an older one can no longer replace a newer one's.

## [1.0.1] - 2026-09-09

### Added

- Favorites. Every currency row now starts with a star; click it to mark that currency. Blizzard's warband badge, which appears when you hover a transferable currency, sits right of the star. Stars are saved for your whole account and never change the order of the list. Tick "Favorites" in the filter menu to see only your starred currencies.
- Filter icon (funnel) next to the search box. Tick "Transferable" to show only the currencies that can be transferred between the characters of your Warband, "Owned" to hide every currency you have none of, "Capped" for currencies at their maximum or this week's cap, "Weekly" for currencies with a weekly earning limit, or "On Backpack" for the ones on your backpack bar, with or without search text. Filters combine. A red x on the icon marks an active filter and clears it.
- Settings gear beside the funnel; it opens the same window as `/ccs settings`.
- "Filters persist between logins" setting, off by default. On, the filters you left ticked are back at your next login.
- More settings: focus the search box when the tab opens, keep the search text while the window is closed, a search delay slider, flat results (currencies only, with their group dimmed after the name), and where the favorite star shows (every row, search results only, or only under the mouse, with starred currencies optionally keeping their star).

### Fixed

- "Match descriptions too" works: the currency list does not carry descriptions, so they are now fetched per currency.

### Changed

- Clicking a result now opens its options right in the results (Unused, Show on Backpack, Transfer) and the search stays. Transfer opens the transfer menu for that currency beside the window and your search stays put. Amounts in the results update as soon as a transfer lands.
- `/ccs <text>` now opens the character window on the Currency tab and searches right away, instead of waiting for you to open the tab. Warband transfers from those results still work.

## [1.0.0] - 2026-09-08

Initial release of Coby's Currency Searcher.

- Search box on the Currency tab of the character window. Matches are shown as you type, in Blizzard's own row style, with no gaps.
- Currencies inside collapsed expansion headers are found without changing your headers.
- Clicking a result selects that currency in Blizzard's own list with its options popup open, so Unused, Show on Backpack and warband Transfer all work from a search. Your headers are restored when you close the tab. In combat a small options popup opens instead.
- Results support tooltips, shift-click linking, and the modified click that toggles the backpack watch.
- Typing a header name (for example "Midnight") shows every currency under it.
- Escape, the clear button, and closing the window all clear the search. Collapsing a header inside the results only hides its rows there.
- "Match descriptions too" option to search description text as well as names.
- `/ccs <text>` searches the Currency tab for the text, or arms the search until you open the tab; `/ccs settings`, `/ccs debug`, `/ccs version`, `/ccs help`.

[Unreleased]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/releases/tag/v1.0.2
[1.0.1]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/releases/tag/v1.0.1
[1.0.0]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/releases/tag/v1.0.0
