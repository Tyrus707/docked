# Play with friends

Switch games' **local wireless** play (Smash, Mario Kart 8 Deluxe, Animal Crossing, Splatoon, Pokémon, Mario Party and most local co-op) works between friends' Macs over the internet. The game thinks everyone is in the same room. Nintendo's online service is never used or contacted, and nothing here works with real Switch consoles.

## For players

1. Get the **friends pass** (`friends.cfg`) from whoever set up your circle, and add it in **Docked › Settings › Friends**.
2. In a game's **Game Settings**, switch on **Play with friends**.
3. Start the game, open its Friends screen (the Friends menu in the menu bar, or press both sticks in) to see your code and add your friends' codes, then use the game's own local wireless mode (for Smash: Local Wireless; Mario Kart: Wireless Play).

Games converted before this version of Docked need **Convert Again** to get the switch.

**Smooth play:** use Ethernet if you can. Mac Wi-Fi pauses briefly now and then to look for AirDrop and Handoff devices, and lockstep games (fighting, racing) feel those pauses as slow motion. If a game still feels slow, set its **Connection smoothing** to Off; for relaxed games (Animal Crossing) Medium can even out a bumpy connection.

Friends you play with see your Mac's internet address, as with any game played directly between two computers. The pass lets anyone who has it into your circle, so send it privately.

## Starting a circle (once, by one person)

Needs a free Cloudflare account and an API token that can edit Workers (and, for the relay, Calls/TURN keys).

```
python3 -I Friends/meeting/setup_meeting.py
```

It puts a small meeting point on your own Cloudflare account (`worker.js`, `core.js`), saves your pass in `~/Library/Application Support/Docked/Friends/friends.cfg`, and never stores the token. Run it again to update the meeting point; `--new-key` replaces the circle's key (everyone then needs the new pass). The meeting point only introduces friends; game traffic goes directly between Macs, or through Cloudflare's TURN relay only when two Macs cannot reach each other.

## How it's built

`engine-patches/` are changes to the conversion engine (nxnative), applied by `apply.sh` on top of the reviewed engine in `ENGINE_PIN` whenever Docked packs an engine (`Bundle/make.sh`, `engine-release.sh`). They add a real `nn::ldn` (local wireless) on a virtual 169.254.77.0/24 network carried in one authenticated, encrypted UDP connection per friend, the meeting point client, NAT traversal (STUN, TURN) and the in-game Friends screen. Everything is off unless the game's `DM_FRIENDS` setting is on. The LDN record layouts follow switchbrew/libnx as collected in nxnative PR #846 (Robii Aragon, MIT).

Slowdown work (patch 0005): lockstep games wait every frame for the other Mac, so any time a packet is held back is time both games stand still. The jitter cushion is now at most 4 ms by default and falls quickly, one spare copy is sent instead of two, and in a room the game log gets a line every 5 seconds with sent/received packets, spare copies, drops, and each friend's ping, worst ping and cushion. Tunables: `DM_FRIENDS_CUSHION_MS` (0 to 25, the game setting), `DM_FRIENDS_COPIES` (0 to 2), `DM_FRIENDS_TRACE=1` (calls, no names or addresses).

**Engine updates:** `bump-engine.sh` stops before changing anything when the patches no longer apply. To refresh them: check out the new engine, `git am` the patches, fix what conflicts, then `git format-patch <new pin>..HEAD -o Friends/engine-patches` and update `engine-patches/BASE`.

**Tests:** in an engine checkout with the patches applied, the friends tests live in `dm/host/tests` (`t_friends_link.c`, `t_friends_net.c`, `t_friends_path.c`, `t_friends_internet.py`); the meeting point's own test is `node Friends/meeting/test/run.mjs`.
