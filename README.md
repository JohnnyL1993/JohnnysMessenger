# Johnny's Messenger

A World of Warcraft 3.3.5a addon for the Warmane private server.

Teams-style whisper messenger. Left pane lists your conversations, right pane shows the open thread.

## Requirements

No other addons required.

## Install

1. Go to [Releases](https://github.com/JohnnyL1993/JohnnysMessenger/releases) and download **`JohnnysMessenger-vX.Y.zip`** from the latest release.
   Don't use GitHub's green **Code → Download ZIP** button or the "Source code" zips. Those unpack as `JohnnysMessenger-main` or `JohnnysMessenger-1.0`, and WoW won't load an addon whose folder name doesn't match.
2. Extract it into `World of Warcraft\Interface\AddOns\`. You should end up with `Interface\AddOns\JohnnysMessenger\JohnnysMessenger.toc`.
3. Restart WoW, or log out to the character screen, and make sure the addon is enabled.

## Updating

Download the latest release zip, delete the old `JohnnysMessenger` folder, and extract the new one in its place.

## Slash commands

| Command | What it does |
| --- | --- |
| `/jm or /messenger` | Open the messenger window |

## Other Johnny's addons

- [Johnny's Raid Comp](https://github.com/JohnnyL1993/JohnnysRaidComp)
- [Johnny's Warmane Addon Hub](https://github.com/JohnnyL1993/JohnnysAddonHub)
- [Johnny's Blacklist](https://github.com/JohnnyL1993/JohnnysBlackList)
- [Johnny's Currency Tracker](https://github.com/JohnnyL1993/JohnnysCurrencyBar)
- [Johnny's Gear Advisor](https://github.com/JohnnyL1993/JohnnysGearAdvisor)
- [Johnny's Raid Browser](https://github.com/JohnnyL1993/JohnnysRaidBrowser)
- [Johnny's Raid Roll](https://github.com/JohnnyL1993/JohnnysRaidRoll)

## Releasing (maintainer notes)

1. Bump `## Version:` in the `.toc`.
2. Commit, then `git tag vX.Y` and `git push && git push --tags`.
3. The **Release** GitHub Action builds the zip and attaches it to the release.
