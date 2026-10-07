# Johnny's Messenger

A World of Warcraft 3.3.5a addon for the Warmane private server.

Teams-style whisper messenger. Left pane lists your conversations, right pane shows the open thread.

## Features

- **Chat bubbles**: their messages on the left, yours on the right. Messages within two minutes of each other are grouped under one name and time. Day separators and a "New messages" divider mark where you left off.
- **Clickable links**: item, spell and achievement links in a message show tooltips and can be clicked. Web addresses open a copy box. Right-click a bubble to copy its text.
- **Contact list**: class icons, online/away/busy/offline dots (from your friends list, guild and group), last-message preview, unread badges and a search box.
- **Right-click a contact** to pin it to the top, mute it, mark it unread, invite them, run `/who`, or remove the conversation.
- **Reply box**: each conversation keeps its own draft. Quick replies are one click away, and Up/Down recalls messages you've sent.
- **Resizable window**: drag the bottom-right corner, or drag the line between the two panes. The window fades when you're not using it.
- **Settings** (gear button in the title bar):
  - Auto-open on incoming whispers
  - Hide whispers from the default chat
  - Whisper sound
  - Hide during combat
  - 12h/24h time
  - Opacity, scale and font size
  - History limits
  - Quick replies
- **Minimap button** with an unread count, a pulse while anything is unread, and the top unread senders in its tooltip.
- **Keybindings** under Key Bindings > AddOns: toggle the window, reply to the last whisper.
- **Update notice**: when another player is running a newer version, a gold "Update available" notice replaces the window title. Click it for a copyable link to the Releases page.

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
| `/jm` or `/messenger` | Toggle the messenger window |
| `/jm reply` | Open the last person who whispered you |
| `/jm settings` | Open settings |
| `/jm version` | Show your version and whether a newer one has been seen |
| `/jm help` | List commands |

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
