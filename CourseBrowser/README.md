# Super Mario Maker 2 Course Browser inside the game window

This adds a small, reversible hook to the **conversion engine**. It uses the engine's existing `WKWebView` support — the same web view offline HTML pages already use — to show a course browser over the game picture, inside the game's own window.

Nothing happens in an ordinary launch. Docked's macOS **File › Super Mario Maker 2 Course Browser…** is the only way in: it starts this one game with `DM_COURSE_BROWSER` pointing at a private mailbox folder, and the host shows the page when the window is ready. There is no in-game shortcut. Docked writes the page and its replies there; the game host reads requests and sends replies back. There is no sign-in, no Nintendo connection, no upload, and no access to the save from the page.

## How to use it

1. In Docked, choose **File › Super Mario Maker 2 Course Browser…**. The game must be converted, closed, and have a save.
2. The game starts with the browser page already shown. Use **Close** on the page to leave it; an ordinary game launch has no browser folder, so nothing in the game can open this page.
3. Browse the **Popular**, **New uploads**, **Castle**, **Puzzle solving**, **Speedruns** and **3D World** shelves. Each shelf is a real question to a public course archive; the page is not a fake feed and is not Nintendo Course World. You can also search by name, style, theme or a nine-character course ID.
4. Choose a card to see its details and its honest preview. If a real thumbnail exists, the page shows it and says so. Otherwise it draws a small diagram from that course's own decrypted level data and says it is a diagram, not a screenshot. If neither exists, it says there is no preview.
5. Pick a **Downloaded Course** slot that already has a course in it.
   - While the game is running, the course is **queued**. Save and quit the game; Docked checks again that it is closed, backs up the save, then writes only that slot's `course_data_*.bcd`.
   - **Play in SMM2** closes the page and hands you back to the game. A later ordinary launch opens that Coursebot slot.

## What is honest about this

This does **not** replace Nintendo's Coursebot menus inside the guest game. No guest function addresses or safe in-memory hooks were available, so nothing in the game binary is patched. The page is a host web view drawn over the game picture, driven by the game's own input hold. It is the closest true in-process in-game UI we can build without guessing at game code.

The "New uploads" shelf reads the last rows of the public archive through `/rows`, because the archive's `/filter` endpoint only sees its first sample. It is honest about being the newest rows in this archive, not a live Nintendo feed.

Coursebot still shows the chosen slot's old thumbnail, title, maker and play stats. Those live in separate files (`course_thumb_*.btl`, `later.dat`) and in `save.dat`. The browser leaves them alone: it changes only `course_data_*.bcd`, after a dated save backup, and only after the game is closed. It does not rewrite `.btl` files, `later.dat` or slot registration in `save.dat`: a disposable public fixture did not pass its CMAC/CRC self-check, so guessing at those formats would risk corrupting a real save. An already-populated Downloaded Course slot is used, so the game has a registration for it. No guest Coursebot menu function was verified, so this cannot truly replace Nintendo's in-game Coursebot UI.

## What is changed

- `engine-patches/0001-…patch` — adds the menu-armed mailbox bridge to `dm/host/hle_web.c` only; no game-window input hook is changed.
- `apply.sh` — applies the patches in order, and has a `--check` mode used by tests and `bump-engine.sh`.
- `Bundle/make.sh` applies it to every engine payload; `engine-release.sh` applies it only to the new engine so deltas stay safe for older engines.
- `Sources/CourseBrowserBridge.swift` — the page, the mailbox, command checks and honest previews.
- `Sources/CourseBrowserView.swift` — model session handling. The old floating panel is no longer opened.
- `Sources/SMM2Courses.swift` — the browse catalog and real archive queries.

The engine patch is plain source, not a binary patch. A patch that no longer applies fails the build loudly; an engine bump refuses to proceed until it is refreshed.

## Removing it

**To stop using the browser without rebuilding:** quit the game and start it the usual way from its icon or Docked's **Play** button. The hook has no folder to read and does nothing. You can also delete the scratch folder:

```
~/Library/Application Support/nxnative/01009B90006DC000/course-browser
```

**To remove the hook from newly converted games:** remove the two lines that call `CourseBrowser/apply.sh` from `Bundle/make.sh` and `bump-engine.sh` (and the `./CourseBrowser/apply.sh` call in `engine-release.sh`), delete this folder, rebuild Docked, then delete and re-convert the game app. Your save is left alone. Re-converting is what removes the hook from a game that was already converted; Docked never overwrites the old `/Applications/Docked.app` or another game's save.

**To remove a queued course:** press **Cancel queue** in the page before quitting the game, or use **Cancel** in the browser. Nothing is written until the game has closed.

## Checks

`./test.sh` checks that the patch still applies to the pinned engine, that the payload carries only the menu-armed hook (no in-game key), that the page uses only the host bridge, that commands refuse bad slots and empty searches, that replies keep their request IDs, that only the intended game gets the environment, and that previews are honest. `./build.sh Docked.app` builds the universal app.
