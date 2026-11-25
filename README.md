<p align="center"><img src="Art/docked.png" width="128" alt="Docked icon"></p>

# Docked

One library for every game you own, on your Mac. Docked turns your Switch games into native Mac apps, plays your other consoles through RetroArch, and keeps them all together with their covers, saves and play time. Free and open source.

### [⬇ Download Docked.zip](https://github.com/Tyrus707/docked/releases/latest/download/Docked.zip)

Free, about 115 MB. macOS 13 or later; see [what you need](#what-you-need) and [how to install or update](#install-or-update).

## What it does

### Turns Switch games into Mac apps

- **Native, not emulated.** [nxnative](https://github.com/seedds/nxnative) converts the game's own code and graphics, and you get an ordinary Mac app.
- **Drop in the files and press Convert.** Docked sorts the game, its update and its DLC by itself, and warns you before you start if something is missing or no one has tested that game yet. It reads `.nsp`, `.xci`, `.nsz`, `.xcz`, `.nup` and dump folders.
- **Queue as many as you like.** They convert one after another, with one progress bar and one time estimate. The queue survives a restart, and one failure doesn't stop the rest.
- **Add an update or DLC later.** Docked reuses the work it has already done and keeps your save.
- **Change how a game runs.** Play with Settings lets you pick frame rate, resolution and language, where the game allows it.
- **Make it for iPhone or iPad** *(experimental)*. Docked prepares a project that Xcode signs with your own Apple account and installs, or makes an `.ipa` file. Needs an iPhone 15 Pro or later, or an iPad with an M1 chip or later, with iOS or iPadOS 26. Not yet tested on a real device.

### Plays your other consoles

Add your own games for 20 more systems and they sit beside your Switch games. They run in [RetroArch](https://www.retroarch.com), if you have it installed.

| | |
|---|---|
| **Nintendo** | NES, SNES, Nintendo 64, Game Boy, Game Boy Color, Game Boy Advance, DS, 3DS, GameCube, Wii |
| **Sega** | Master System, Genesis, Game Gear, Saturn, Dreamcast |
| **Sony** | PlayStation, PlayStation 2, PSP |
| **Others** | TurboGrafx-16, Atari 2600 |

### Looks and feels like a console

- **Built for the sofa.** Opens in full screen, and you can move around it with a controller or the arrow keys.
- **Covers made from each game's own art**, or drop any picture on a game.
- **Theme music.** Give a game its own tune, and it plays while the game is selected.
- **Pick up where you left off.** Recent games come first, with how long you've played each one.
- **Stays light.** It's a small native app, and it respects Reduce Motion and light or dark mode.

### Keeps things in order

- **Favourites, progress and collections.** Smart collections fill themselves, such as games you haven't played for a month.
- **Clean Up** shows what each game left behind and how big it is. You choose what goes. Your original files only ever go to the Trash, and games and saves stay.
- **One-click updates.** Docked checks that an update is genuine before installing it, and keeps the old version.

No games, keys, firmware or console files are included, and none may be posted here.

## What you need

| | Needs |
|---|---|
| Library and other consoles | macOS 13 or later, Apple or Intel |
| Playing converted games | macOS 26.6 or later, Apple chip |
| Converting games | macOS 26.6 or later, Apple chip, [Xcode 27.2](https://developer.apple.com/download/all/) |
| Making a game for iPhone or iPad | The same, plus Apple's iOS tools and [XcodeGen](https://github.com/yonaskolb/XcodeGen) |

Docked has been tested on macOS 27.2. Older versions and Intel are built for but not yet tested on real Macs. Games that use OpenGL may need macOS 27 to convert.

## Install or update

1. Download [**Docked.zip**](https://github.com/Tyrus707/docked/releases/latest/download/Docked.zip), unzip it and open **Docked**. Older versions are under [Releases](https://github.com/Tyrus707/docked/releases).
2. Docked is not notarised by Apple. If macOS blocks it, open **System Settings > Privacy & Security** and choose **Open Anyway**.
3. Docked offers to move itself to Applications. **Already have an older Docked?** It offers to update that one instead. Your games, saves and settings stay, and the old version is kept in `Dockside/Backups` in your home folder. You can also drag it to Applications yourself and choose Replace.
4. To convert games, follow the guide in Docked. The conversion tools are inside the app; Xcode is not.

After that, Docked tells you when there is a new version and installs it for you. If macOS stops it, allow **Docked** under **Privacy & Security > App Management**. Version 1.1 and older can't update themselves, so download the new one as above.

A converted game's graphics are prepared for the Mac that made it. On a different chip or major macOS version the first start is slower.

## Your games only

Use Docked only with games and system files from your own console, where your local law allows it. Docked needs your own `prod.keys` file for some file types. It stays on your Mac: Docked remembers where it is and never copies or sends it.

Docked is not affiliated with, endorsed by or connected to Nintendo or any other company. Console and game names belong to their owners and are used only to say what works with what.

## Privacy

Docked collects nothing and has no account. It asks GitHub for the newest version number once when it opens, which you can switch off in Settings, and when you choose **Check for Updates**. An update is downloaded only when you press **Update**. Help and setup links open in your browser. Covers come from your own games or pictures you choose; none are downloaded. **Copy Report** takes out your name, folders, addresses and anything like a key, but read a report before you post it.

## Build it yourself

```
./test.sh                       # tests (Xcode needed)
./build.sh Docked.app           # the app alone; setup.sh then installs the tools with Homebrew
./build.sh Docked.app tools.xz  # with the tools inside, made by Bundle/make.sh
```

`Bundle/make.sh` packs what `setup.sh` installed, with a pinned [standalone Python](https://github.com/astral-sh/python-build-standalone/releases/tag/20261124) placed in `~/Dockside/python-standalone`. Every pinned version and fingerprint is in those scripts.

## Help

Open an issue with your macOS version, your Mac's chip, and what Docked says under **Details**. Do not attach games, keys or logs that contain them.

## Licence and credits

Docked is under the [MIT licence](LICENSE). It would not exist without [nxnative](https://github.com/seedds/nxnative) by seedds (MIT). Everything else inside the download is listed in [THIRD-PARTY.md](THIRD-PARTY.md).
