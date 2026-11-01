# Timers for Ashita v4 / VanaCore

Timer bars for your **recasts**, the buffs you cast (**Durations**) and the debuffs you land on monsters (**Debuffs**),
each in its own panel you can place, size, sort, filter and theme.

Version 2.0, made for CatsEyeXI (VanaCore). It also runs on plain Ashita v4, where the themes use ImGui's own font.

## Install

1. Download `timers-2.0.zip` from the [latest release](https://github.com/Benthere407/Timers/releases/latest).
2. Unzip it into your `addons` folder (for VanaCore: `VanaCore\addons\ashita\`), so you have `addons\...\timers\timers.lua`.
   Replacing an older Timers? Delete the old `timers` folder first; your settings are kept.
3. In game: `/addon load timers`. Add that line to your startup script to load it every time.

## Commands

| Command | What it does |
| --- | --- |
| `/timers` | Open or close the settings window |
| `/timers lock` / `/timers unlock` | Stop or allow moving the panels |
| Shift + drag | Move a panel |

## What's new in 2.0

- **A new settings window** in the VanaCore menu style: a sidebar with search, pages for each panel (Layout, Bars, Text,
  Icons, Filters), a reset-to-defaults icon on every section, and a `< 100% >` window scale in the header.
- **Themes**: Default, YunaUI, YunaVEXWB, YunaVEXP, YunaHEX and Classic.
- **Custom themes**: the built-in themes never change. Change a bar, text or icon setting while a panel uses one and a
  custom theme is made from it (e.g. "Classic (custom)") for every panel using it. Custom themes are files,
  `themes\<name>.lua`, saved as you change them, so every character can pick them. Rename, duplicate or delete them on
  the Theme page.
- **Copy this look**: give one panel's look to the others (optionally its bar colour too).
- **Filters**: an Active view listing the timers a panel has right now, so you can hide or show them in one click.
  Filter sets per job, loaded when you change job.
- **Party buffs**: timers for every party member your AoE buffs land on, optionally combined into one "(Party)" timer.
- **Debuffs** from the whole alliance's casts.
- Fixes: other players' identical buffs credited to you, rows swapping places, the panels' mouse-wheel error, and a
  crash when a party member is out of range.

## Themes

| Theme | Look |
| --- | --- |
| Default | Ashita's fonts and bars |
| YunaUI | YunaUI's Timers: white names with a thin dark edge, the time in the bar's colour, thin glowing bars that drain |
| YunaVEXWB | YunaUI's Vex mode: white HP / blue MP bars on a dark plate |
| YunaVEXP | YunaUI's Vex Damage Meter: thin pink-to-violet bars with a white dot at the end |
| YunaHEX | YunaUI's Hex link: gold and azure bars in a gold-edged frame with cut corners |
| Classic | The game's blue menu window and square gauges |

A theme is how the bars, text and icons look. Each panel's Layout (size, padding, background) stays its own.

## Credits

- Timers by **The Mystic** and **Shiyo** - https://github.com/lenonk/Timers. Version 2.0 by **Benthere407**.
- Based on YunaUI by Yunas - https://github.com/YunasXI/yunaui
  (the YunaUI themes' look and bar drawing; see `NOTICE-YunaUI`).
- Font: TeX Gyre Adventor (GUST Font License, see `fonts/GUST-texgyreadventor.txt`).
- The settings window uses the vcmenu library (`vcmenu.lua`), inspired by the VanaCore menus by Vekien and Josh.Xero.
- See `Thanks.md` for the people who helped with the original addon.

## Licence

GNU General Public License v3.0 (see `LICENSE`). The material from YunaUI also carries its additional attribution term
(see `NOTICE-YunaUI`).

## Notes

- Not every ability and spell can be tested on every job. If something isn't timed right, please open an issue.
- Recasts use the icon of a status effect with the same name, where there is one.
