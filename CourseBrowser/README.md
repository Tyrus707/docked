# Super Mario Maker 2 Course Browser inside the game window

This adds a small, reversible hook to the **conversion engine**. It uses the engine's existing `WKWebView` support — the same web view offline HTML pages already use — to show a course browser over the game picture, inside the game's own window.

Nothing happens in an ordinary launch. The hook wakes only when Docked starts *this one game* with `DM_COURSE_BROWSER` pointing at a private mailbox folder. Docked writes the page and its replies there; the game host reads requests and sends replies back. There is no sign-in, no Nintendo connection, no upload, and no access to the save from the page.

## How to use it

1. In Docked, open the game's **Saves** menu and choose **Course Browser…** (or use **File › Super Mario Maker 2 Course Browser…**).
2. The game starts. Press **F6** in the game window to show the page; press it again, or **B**, to close it.
3. Search by course name or enter a nine-character course ID. Choose a course to see its preview.
4. Pick a **Downloaded Course** slot that already has a course in it.
   - While the game is running, the course is **queued**. Save and quit the game; Docked checks again that it is closed, backs up the save, then writes only that slot's `course_data_*.bcd`.
   - If the game is closed, Docked does the same checks and write straight away.

If a real JPEG/PNG thumbnail is available, the page shows it and says so. Otherwise it draws a small diagram from that course's own decrypted level data and says it is a diagram, not a screenshot. If neither exists, it says there is no preview. It never shows made-up artwork.

## What is honest about this

This does **not** replace Nintendo's Coursebot menus inside the guest game. No guest function addresses or safe in-memory hooks were available, so nothing in the game binary is patched. The page is a host web view drawn over the game picture, driven by the game's own input hold. It is the closest true in-process in-game UI we can build without guessing at game code.

Coursebot still shows the chosen slot's old thumbnail, title, maker and play stats. Those live in separate files (`course_thumb_*.btl` and save metadata). This build changes only `course_data_*.bcd`, after a dated save backup, and only after the game is closed.

## What is changed

- `engine-patches/0001-…patch` — adds the dormant F6 request and mailbox bridge to `dm/host/hle_web.c` and `dm/host/front_mac.m`.
- `apply.sh` — applies the patches in order, and has a `--check` mode used by tests and `bump-engine.sh`.
- `Bundle/make.sh` applies it to every engine payload; `engine-release.sh` applies it only to the new engine so deltas stay safe for older engines.
- `Sources/CourseBrowserBridge.swift` — the page, the mailbox, command checks and honest previews.
- `Sources/CourseBrowserView.swift` — model session handling. The old floating panel is no longer opened.

The engine patch is plain source, not a binary patch. A patch that no longer applies fails the build loudly; an engine bump refuses to proceed until it is refreshed.

## Removing it

**To stop using the browser without rebuilding:** quit the game and start it the usual way from its icon or Docked's **Play** button. The hook has no folder to read and does nothing. You can also delete the scratch folder:

```
~/Library/Application Support/nxnative/01009B90006DC000/course-browser
```

**To remove the hook from newly converted games:** remove the two lines that call `CourseBrowser/apply.sh` from `Bundle/make.sh` and `bump-engine.sh` (and the `./CourseBrowser/apply.sh` call in `engine-release.sh`), delete this folder, rebuild Docked, then delete and re-convert the game app. Your save is left alone. Re-converting is what removes the hook from a game that was already converted; Docked never overwrites the old `/Applications/Docked.app` or another game's save.

**To remove a queued course:** press **Cancel queue** in the page before quitting the game, or use **Cancel** in the browser. Nothing is written until the game has closed.

## Checks

`./test.sh` checks that the patch still applies to the pinned engine, that the payload carries it, that the page uses only the host bridge, that commands refuse bad slots and empty searches, that replies keep their request IDs, that only the chosen game gets the environment, and that previews are honest. `./build.sh Docked.app` builds the universal app.
