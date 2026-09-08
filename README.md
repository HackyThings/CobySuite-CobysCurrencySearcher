# Coby's Currency Searcher

<p align="center">
  <img src="https://raw.githubusercontent.com/HackyThings/CobySuite-CobysCurrencySearcher/main/.publish-meta/icon/cobys-currency-searcher-224.jpg" width="160" alt="Coby's Currency Searcher">
</p>

A search box for the Currency tab of the character window in WoW Midnight (12.1).

If you've ever opened the Currency tab to check one number, scrolled past six expansions of headers, opened the wrong one, and closed the window without finding it... yeah. Coby's Currency Searcher puts a search box on the tab. Type a few letters and the list shrinks to what you're looking for.

## The Problem

Blizzard's Currency tab lists every currency your character has ever touched, grouped under expansion headers and sub-headers, and there is no way to search it. Collapsed headers hide their contents completely, so a currency you filed away last expansion is invisible until you remember where it lives. The filter dropdown only switches between this character's currencies and the ones that can move across your Warband.

Older search addons hid rows after Blizzard drew the list, which left the tab full of empty gaps. Coby's Currency Searcher shows only the matching rows, in Blizzard's order and Blizzard's own row style, so it looks like the tab was always that short. Blizzard's list itself is left untouched underneath, which is what keeps warband transfers working.

## How It Works

1. **Open the character window and pick the Currency tab.** The search box sits between your portrait and the filter dropdown, in Blizzard's own search-box style.
2. **Type.** After a short pause only the matching currencies are shown. Headers stay in place above their matches so you can see where each one lives. No gaps.
3. **Collapsed headers are searched too.** Currencies inside headers you keep collapsed are found; your headers are never changed.
4. **Type a header name to see the whole group.** Searching "Midnight" or "Dungeon and Raid" shows every currency under that header.
5. **Clearing is one keypress.** Escape, the clear button, or closing the window all clear the search, so the tab opens clean next time.

Edge cases it handles:

- **Nested sub-headers.** A collapsed sub-header inside a collapsed expansion header is found too. Same-named sub-headers under different parents are kept apart.
- **Headers in the results.** Collapse a header in the results and only the results hide its rows; your real headers are untouched.
- **Clicking a result selects it for real.** The search closes, Blizzard's list folds down to that currency's group, and its options popup opens: Unused, Show on Backpack, and Transfer, all Blizzard's own, so a warband transfer from a search result works. Your headers go back to how you had them when you close the tab.
- **Row actions.** Tooltips, shift-click to link, and the modified click that toggles the backpack watch work on results the same way they do on Blizzard's rows.
- **Account-wide view still loading.** If Blizzard is still fetching account currency data when you type, the results fill in the moment the data arrives.
- **Logging in during combat.** Addons cannot build frames in combat, so the search box is added the moment combat ends. Nothing to do on your end.

## Install

**CurseForge:** https://www.curseforge.com/wow/addons/currency-searcher

**Manual:** Drop the `CobysCurrencySearcher` folder into your `Interface/AddOns/`. No dependencies.

## Slash Commands

```
/ccs <text>       Search the Currency tab for <text> (runs when you open the tab)
/ccs settings     Open the settings window
/ccs debug        Toggle the debug log window
/ccs version      Print the addon version
/ccs help         Command list
```

`/cobyscurrencysearcher` works the same as `/ccs`.

## Settings

Open with `/ccs settings`. One option, and it applies the moment you click it.

**Search**
- Match descriptions too (default off. Also matches the search text against each currency's description, not only its name. Handy when you remember what a currency buys but not what it is called.)

## Troubleshooting

**A currency I know I have does not show up.**

- Check the filter dropdown next to the search box. Blizzard's own filter (Character or Transferable) still applies on top of the search, so a currency hidden by that filter stays hidden.
- Currencies marked as unused live under the Unused header. The search looks there too, so if it still does not appear, this character has not discovered that currency yet.
- Try turning on "Match descriptions too" in `/ccs settings` if you only remember what the currency is for.

**There is no search box on the Currency tab.**

- If you logged in during combat, the box appears once combat ends.
- Run `/ccs debug`. If the log says the Currency tab is missing or changed shape, another addon has replaced or reshaped the tab, or a WoW patch changed it. Either way, the log is what I need to fix it (see below).

**I clicked a result and got a message to scroll down to it.**

- The list is folded around that currency's group, but the group itself is taller than the window, so the row is just below the fold. Scroll down and click it; everything from there on is Blizzard's own.

**In combat, clicking a result opens a small options popup instead.**

- Selecting a currency in Blizzard's list is only possible out of combat. The popup covers Unused and Show on Backpack; its Transfer button brings the full list back so you can find the currency there.

**`/ccs <text>` says the search box is not available.**

- Same cause as above. The command needs the box to be installed on the tab first.

## License

GPL-2.0. See [LICENSE](LICENSE).

## Issues / Feedback

For bug reports, the cleanest path is the debug log. It's self-contained: it includes the addon version, your WoW build, a snapshot of every setting, and a timestamped event timeline. No need to paste anything else.

**How to capture and send:**

1. Reproduce the issue.
2. Run `/ccs debug` to open the debug window. Copy the last ~250 entries.
3. Email them to **hackythings@gmail.com** with a sentence about what you were doing.

**Other channels:**

- **BugSack errors:** whisper the report straight to **Figment-Illidan** in-game. BugSack copies the stack trace for you. Mention how to reproduce if you can.
- **CurseForge comments:** drop a note on the [project page](https://www.curseforge.com/wow/addons/currency-searcher). Best for general feedback and quick questions.
- **GitHub issues:** [open one here](https://github.com/HackyThings/CobySuite-CobysCurrencySearcher/issues). Best for reproducible bugs and feature proposals where back-and-forth helps. Attach the debug-log paste here too if it's relevant.
