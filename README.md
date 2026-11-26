<p align="center"><img src="Art/hero.png" alt="Docked: your Switch games as real Mac apps, plus 20 classic consoles, all in one library"></p>

<p align="center"><b>Docked turns the Switch games you own into real Mac apps, and puts your retro classics right beside them.</b><br>
One tidy library for NES to Switch. Free, open source and light.</p>

<p align="center">
  <a href="https://github.com/Tyrus707/docked/releases/latest/download/Docked.dmg"><b>⬇&nbsp; Download Docked for Mac</b></a>
  &nbsp;·&nbsp; about 115 MB<br>
  <sub>Library and retro games: macOS 13 or later. Switch games: macOS 26.6 or later on Apple silicon (<a href="#what-you-need">details</a>).</sub>
</p>

<p align="center">
  <a href="https://github.com/Tyrus707/docked/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Tyrus707/docked?label=version&color=1F6675"></a>
  <a href="LICENSE"><img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-1F6675"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-13%2B-1F6675?logo=apple&logoColor=white">
</p>

---

## Why Docked

Playing your Switch games on a Mac usually means an emulator, a pile of settings and a window that never quite feels at home. Docked takes a different route. It hands each game to [nxnative](https://github.com/seedds/nxnative), which converts the game's own code and graphics, and what comes out is an ordinary Mac app. You open it from the Dock like anything else.

Docked does the bookkeeping around that. It works out which file is the game, which is the update and which is the DLC, tells you before you start if something is missing, and lines up as many games as you like. When it's done, your games sit together with their covers, saves and play time.

It's built to stay out of your way: a light native app that opens fast, follows your Mac's light or dark mode, and works just as well with a controller from the sofa.

## Your classics, too

Docked isn't only for Switch. Bring the games you've kept from older consoles, from the NES and Game Boy to the PlayStation 2 and Wii, and they share the same shelf: same covers, same favourites, same "pick up where you left off". Your whole collection, one place, one controller.

| | |
|---|---|
| **Nintendo** | NES, SNES, Nintendo 64, Game Boy, Game Boy Color, Game Boy Advance, DS, 3DS, GameCube, Wii |
| **Sega** | Master System, Genesis, Game Gear, Saturn, Dreamcast |
| **Sony** | PlayStation, PlayStation 2, PSP |
| **Others** | TurboGrafx-16, Atari 2600 |

There's nothing else to install. The first time you add a game for one of these consoles, Docked downloads [RetroArch](https://www.retroarch.com) and the right emulator for that console from libretro, keeps them inside Docked's own folder (not in Applications), and starts your games in it with a click. You never have to open RetroArch yourself.

Docked works out the console from the file. For disc images such as `.iso`, `.cue` and `.chd`, it looks inside the disc, and only asks you when it can't tell. Where emulators differ, Docked picks the most accurate one first, such as bsnes for SNES, SameBoy for Game Boy and Beetle for PlayStation and Saturn.

Saturn and PlayStation 2 need the BIOS from your own console, and PlayStation plays best with one. Docked asks for it when you add the game, checks it, and keeps a copy. It never downloads a BIOS for you.

## How it works

For Switch games:

1. **Drop in your games.** Drag your own `.nsp`, `.xci`, `.nsz`, `.xcz` or `.nup` files, or a dump folder, onto Docked.
2. **Press Convert.** Docked checks everything first, then converts the games one after another with a single progress bar and time estimate. If you quit, the queue is still there next time.
3. **Play.** Each game becomes its own Mac app in your library, ready to launch with a click or a controller.

For retro games, just drag them in. Docked works out the console from the file (and simply asks if it could be more than one), then adds the game to your library.

The first time you convert, Docked walks you through the one-off setup. The conversion tools come inside the app; you only need to install Apple's Xcode yourself.

## Get started

1. [Download **Docked.dmg**](https://github.com/Tyrus707/docked/releases/latest/download/Docked.dmg) and open it.
2. Drag **Docked** onto the **Applications** folder in the window that appears, then open it from Applications. If you already have an older Docked, choose **Replace**: your games, saves and settings stay.
3. Docked isn't notarised by Apple yet, so macOS stops it the first time. Open **System Settings › Privacy & Security** and choose **Open Anyway**. You only need to do this once.

Prefer a zip? [**Docked.zip**](https://github.com/Tyrus707/docked/releases/latest/download/Docked.zip) has the same app: unzip it, open Docked, and it offers to move itself to Applications.

From then on Docked lets you know when there's a new version and installs it for you, after checking the update really came from this project. Your previous version is kept in `Docked/Backups` in your home folder, just in case.

### What you need

| To… | You need |
|---|---|
| Use the library and play retro games | macOS 13 or later, Apple chip or Intel. RetroArch (about 230 MB) is downloaded the first time |
| Play converted Switch games | macOS 26.6 or later on an Apple chip |
| Convert Switch games | The same, plus [Xcode 27.2](https://developer.apple.com/download/all/) |

Docked is tested on macOS 27.2. Older versions and Intel Macs are supported in the build but haven't been tried on real hardware yet, so reports are very welcome.

---

## A closer look

<details>
<summary><b>Converting games</b></summary>

<br>

- **Native, not emulated.** nxnative converts the game itself, so you get a regular Mac app rather than a game running inside another program.
- **Knows what's what.** Docked sorts the game, its update and its DLC for you, and warns you before starting if a piece is missing or nobody has tested that game yet.
- **A queue that keeps going.** Add as many games as you like. The queue survives a restart, and if one game fails the rest carry on.
- **Add an update or DLC later.** Docked reuses the work it has already done and keeps your save.
- **Play with Settings.** Choose frame rate, resolution and language, where the game allows it.
- **Checked before it's called done.** When a game finishes, Docked makes sure the app is whole, holds everything it needs and has a signature that matches. If something is off, such as graphics that were only partly prepared, Docked converts the game once more, which redoes only the missing part. If it's still not right, Docked tells you and keeps what it needs to try again quickly.
- **A newer engine, without a new Docked.** New game profiles and fixes arrive as engine updates, signed like Docked's own. Docked checks every file, tries the new engine, and only swaps it in while nothing is converting. The previous engine is kept, and **Settings › Setup** can switch back.
- **Clear reports.** If something goes wrong, **Report Problem** copies a summary and opens a new GitHub issue to paste it into, with your name, folders and anything that looks like a key taken out.

A converted game's graphics are prepared for the Mac that made it. On a different chip or major macOS version, its first start takes a little longer. Games that use OpenGL may need macOS 27 to convert.

</details>

<details>
<summary><b>The library</b></summary>

<br>

- **An organized folder, wherever you want it.** One library folder, even on an external SSD, with a folder for each console and each game named after itself. **Organize Library** shows you what it will move before anything moves, and saves follow their game.
- **Bring in what you already have.** **Find Games on This Mac** finds games Docked converted before and games in OpenEmu, RetroArch and Ryujinx, or look through any folder or drive. Docked asks whether to copy, move or leave the files where they are, and can remember your answer.
- **Watched folders.** New games in a folder you choose are added on their own and stay where they are. A drive's games show as not connected while it's unplugged, and come back when it's plugged in.
- **Feels like a console.** Docked opens filling the screen, and you can get around with a controller or the arrow keys.
- **Couch Mode.** For the TV: press the TV button, Command-Shift-B, or your controller's Home button, and your library goes full screen, one shelf at a time, with the chosen game's art behind it, soft menu sounds and its theme music. B or Escape takes you back.
- **Covers made from each game's own art**, or drop any picture onto a game.
- **Covers and details found for you.** Add a game from another console and Docked can fill in its box art, year, maker, genre and description, the way a launcher's game database does. It matches the file's checksum or disc serial first, then its name, and asks you when more than one game fits. Off until you say yes.
- **Theme music.** Give a game its own tune and it plays while that game is selected.
- **Pick up where you left off.** Recent games come first, with how long you've played each one.
- **Favourites and collections.** Smart collections fill themselves, such as games you haven't played in a month.
- **Easy on the eyes.** Follows your Mac's light or dark mode and respects Reduce Motion.
- **Clean Up** shows what each game left behind and how much room it takes. You choose what goes. Your original files only ever go to the Trash, and your games and saves stay put.

</details>

<details>
<summary><b>iPhone and iPad (experimental)</b></summary>

<br>

Docked can prepare a game for iPhone or iPad as an Xcode project that signs with your own Apple account and installs, or as an `.ipa` file. It needs an iPhone 15 Pro or later, or an iPad with an M1 chip or later, running iOS or iPadOS 26. On the Mac you'll need the same as for converting, plus Apple's iOS tools and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

This hasn't been tested on a real device yet, so treat it as an early preview.

</details>

<details>
<summary><b>Updating from an older version</b></summary>

<br>

Download the new version, open it and drag Docked to Applications, choosing **Replace**. Your games, saves and settings stay. Or open Docked straight from the download: it offers to replace the old one for you and keeps the old version in `Docked/Backups`.

Versions 1.1 and older can't update themselves, so download the new one by hand once. If macOS blocks an automatic update, allow **Docked** under **System Settings › Privacy & Security › App Management**.

</details>

<details>
<summary><b>Build it yourself</b></summary>

<br>

```sh
./test.sh                       # run the tests (needs Xcode)
./build.sh Docked.app           # the app alone; setup.sh then installs the tools with Homebrew
./build.sh Docked.app tools.xz  # with the tools inside, made by Bundle/make.sh
Bundle/dmg.sh Docked.app        # Docked.dmg: the drag-to-Applications download
```

`Bundle/make.sh` packs what `setup.sh` installed, with a pinned [standalone Python](https://github.com/astral-sh/python-build-standalone/releases/tag/20261124) placed in `~/Docked/python-standalone`. The engine's pinned commit and the fingerprints of its prebuilt tools are in [`ENGINE_PIN`](ENGINE_PIN); the other pinned versions are in those scripts. A release carries **Docked.dmg** and **Docked.zip** (the same full app) plus **Docked-Update.zip** and its `.sig`, which the built-in updater downloads.

**Moving to a newer engine.** nxnative changes every day, and its game profiles decide which games work, so Docked follows it in reviewed steps:

```sh
./bump-engine.sh [commit]   # shows new and changed game profiles, stops if a prebuilt tool changed, writes ENGINE_PIN, runs the tests
./build.sh Docked.app       # then convert one or two of your own games with it
./engine-release.sh         # signs that engine and offers it to every Docked as an engine update
```

`engine-release.sh` uploads to one pre-release tagged `engine`: the whole engine, and smaller packs with only what changed since engines players are likely to have. It signs `engine.json`, which names the engine's commit, date and the SHA-256 of every file, with the same key as Docked's own updates (from `DOCKED_SIGNING_KEY` or the Keychain, never the repository). Docked uses an engine only if that signature holds, the files match, it is newer than the one Docked was built with, and it starts. An engine that needs other Python packages can't go out this way; it needs a full Docked release.

</details>

---

## Your games, your Mac

**Privacy.** Docked has no account and collects nothing. When it opens, it asks GitHub for the newest version numbers of Docked and its engine (you can turn that off in Settings), and it only downloads an update when you press **Update** or **Update Engine**. The first time you add a game for another console, it downloads RetroArch and that console's emulator from libretro's own server, `buildbot.libretro.com`, and nothing about you or your games is sent. Switch covers come from your own games, and any cover can be a picture you pick.

**Covers and details**, for games from other consoles, are found only if you say yes when Docked first asks (or turn on **Find covers and details** in Settings). Docked then downloads libretro's public game list for that console once, from a fixed version on GitHub that it checks before use, and compares your files with it on your Mac: their checksums, serials and names are never sent. For a matched game it downloads the box art from [libretro-thumbnails](https://github.com/libretro-thumbnails/libretro-thumbnails) on GitHub, also at a fixed version (and, the first time the game is chosen in Couch Mode, an in-game picture from the same place), and, when the list has no description, looks the game's name up on Wikipedia. Those two see the game's name and nothing else. For a Switch game, Couch Mode shows its eShop banner, fetched once by title ID from the [nlib](https://github.com/ghost-land/Nlib-API) title API (only the title ID is sent). Everything is kept in `Docked/Metadata`, so each game is looked up once.

**Your own games only.** Use Docked with games and system files from your own console, where your local law allows it. Some file types need your own `prod.keys`; Docked remembers where it is and never copies or sends it. No games, keys, firmware or console files are included with Docked, and please don't post any here.

Docked is not affiliated with, endorsed by or connected to Nintendo or any other company. Console and game names belong to their owners and are used only to say what works with what.

## Need a hand?

[Open an issue](https://github.com/Tyrus707/docked/issues/new) and include your macOS version, your Mac's chip, and what Docked shows under **Details**. **Report Problem** is a good start, but give it a quick read before posting, and never attach games, keys or logs that contain them.

## Credits

Docked is free under the [MIT licence](LICENSE). It wouldn't exist without [nxnative](https://github.com/seedds/nxnative) by seedds (MIT). Everything else inside the download is listed in [THIRD-PARTY.md](THIRD-PARTY.md). Game details come from the [libretro database](https://github.com/libretro/libretro-database) (CC BY-SA 4.0) and descriptions marked as such from Wikipedia (CC BY-SA 4.0); box art from [libretro-thumbnails](https://github.com/libretro-thumbnails/libretro-thumbnails). None of them are part of the download: Docked fetches them only when you ask it to.
