# What is inside the download

Docked itself is under the [MIT licence](LICENSE). Its download carries the parts below, unchanged except that library paths were made relative. Each keeps its own licence. The texts are in [Licences](Licences) here, and inside the app in `Docked.app/Contents/Resources/Licences` (from 1.3; earlier downloads carry only the licences that came inside each part).

| Part | Version | Licence | Source |
|---|---|---|---|
| nxnative (the conversion engine, and its own [third-party parts](https://github.com/seedds/nxnative/blob/01439b0fe923929d275e2fd4337cbdf08b54fcfd/dm/third_party/README.md)) | 01439b0fe923 | MIT | https://github.com/seedds/nxnative |
| Play with friends (Friends/engine-patches, Friends/meeting) | | MIT, as Docked; LDN layouts after switchbrew/libnx (ISC) and nxnative PR #846 (MIT) | https://github.com/seedds/nxnative/pull/846 |
| Python (python-build-standalone, with OpenSSL, SQLite, libffi, zlib and others) | 3.14.10+20261124 | PSF; OpenSSL is Apache-2.0, and each other part keeps its own licence (listed in that release) | https://github.com/astral-sh/python-build-standalone |
| SPIRV-Cross (prebuilt, part of nxnative) | as pinned by nxnative | Apache-2.0 (text in the engine's `dm/gfx/tools/spirv_cross_bin`) | https://github.com/KhronosGroup/SPIRV-Cross |
| glslang | 16.6.0 | BSD, MIT, Apache-2.0, GPL-3.0-or-later | https://github.com/KhronosGroup/glslang |
| SPIRV-Tools | 1.4.363.0 | Apache-2.0 | https://github.com/KhronosGroup/SPIRV-Tools |
| Zstandard | | BSD-3-Clause or GPL-2.0 | https://github.com/facebook/zstd |
| liblz4 | | BSD-2-Clause | https://github.com/lz4/lz4 |
| liblzma (XZ Utils) | | 0BSD | https://github.com/tukaani-project/xz |
| blessed (Python) | 1.53.0 | MIT | https://pypi.org/project/blessed/1.53.0/ |
| capstone (Python) | 5.0.9 | BSD License | https://pypi.org/project/capstone/5.0.9/ |
| enlighten (Python) | 1.14.1 | MPLv2.0 | https://pypi.org/project/enlighten/1.14.1/ |
| fonttools (Python) | 4.68.0 | MIT | https://pypi.org/project/fonttools/4.68.0/ |
| jinxed (Python) | 2.1.1 | MPLv2.0 | https://pypi.org/project/jinxed/2.1.1/ |
| lz4 (Python) | 4.4.5 | BSD License | https://pypi.org/project/lz4/4.4.5/ |
| nsz (Python) | 5.0.0 | MIT License | https://pypi.org/project/nsz/5.0.0/ |
| numpy (Python) | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | https://pypi.org/project/numpy/2.5.4/ |
| pillow (Python) | 13.0.0 | MIT-CMU | https://pypi.org/project/pillow/13.0.0/ |
| prefixed (Python) | 0.9.0 | MPLv2.0 | https://pypi.org/project/prefixed/0.9.0/ |
| pycryptodome (Python) | 4.6.0 | BSD-2-Clause AND Unlicense AND MIT | https://pypi.org/project/pycryptodome/4.6.0/ |
| texture2ddecoder (Python) | 1.0.6 | MIT License | https://pypi.org/project/texture2ddecoder/1.0.6/ |
| wcwidth (Python) | 0.9.5 | MIT License | https://pypi.org/project/wcwidth/0.9.5/ |
| zbic (Python) | 1.0.1.post1 | GPLv2 | https://pypi.org/project/zbic/1.0.1.post1/ |
| zstandard (Python) | 0.25.0 | BSD-3-Clause | https://pypi.org/project/zstandard/0.25.0/ |

The complete source of zbic (GPL version 2), as used, is in [GPL-source](GPL-source) here and, from 1.3, inside the app in `Contents/Resources/GPL-source`.

The nxnative engine is carried whole at the pinned commit, including its own per-game notes and data. Its authors state that nothing from any game is in it, and no keys or firmware are.

RetroArch and its cores are not included in the download. The first time a game for another console is added, Docked downloads the official, unchanged RetroArch build (version 1.22.2, checked against its SHA-256) and the cores it needs from libretro's buildbot, keeps them in `~/Docked/RetroArch`, and starts RetroArch as a separate program. RetroArch is GPL-3.0 (source: https://github.com/libretro/RetroArch); each core keeps its own licence, mostly GPL, and a few (such as Snes9x and Genesis Plus GX) allow only non-commercial use, which Docked, being free, respects. Because Docked runs RetroArch as its own program and does not link to it or ship it, the GPL does not extend to Docked; Docked's MIT licence is GPL-3.0-compatible in any case. The icon and artwork were made for Docked.

Sunshine is not included in the download either. When TV streaming is switched on, Docked uses an already-installed Sunshine only if its bundle identity and signature check out; otherwise it downloads the newest stable macOS release from GitHub, checks the SHA-256 published with that release and its signature, and keeps it in `~/Library/Application Support/Docked/Streaming`. It runs as a separate program under its own GPL-3.0 licence (source: https://github.com/SunshineStream/Sunshine). Docked does not link to it or ship it, so the GPL does not extend to Docked; Docked's MIT licence is GPL-3.0-compatible in any case.

Retro looks and controller profiles are not included either. When first needed, Docked downloads libretro's slang shader collection (`shaders_slang.zip`, each shader under its own licence, mostly GPL or public domain; source: https://github.com/libretro/slang-shaders) and controller profiles (`autoconfig.zip`; source: https://github.com/libretro/retroarch-joypad-autoconfig) from libretro's buildbot into `~/Docked/RetroArch`. RetroArch reads them; Docked does not link to them. RetroAchievements (https://retroachievements.org) is an optional free service: Docked sends the player's user name and password once to get a sign-in token, keeps only the token (in the Keychain), and passes it to RetroArch for each game.

The console icons in the sidebar are the controller drawings of Controllercons 2.1 by Kieran McClung (https://controllercons.github.io), solid style, under the SIL Open Font License 1.1 ([Licences/Controllercons.txt](Licences/Controllercons.txt)). Docked carries their outlines as path data in `Sources/ControllerArt.swift`. The handheld drawings are Docked's own.
