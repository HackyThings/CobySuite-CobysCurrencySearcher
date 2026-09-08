# Changelog

All notable changes to Coby's Currency Searcher are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), version numbering follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/releases/tag/v1.0.0
