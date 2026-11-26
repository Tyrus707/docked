# Play with friends

Switch games' **local wireless** play (Smash, Mario Kart 8 Deluxe, Animal Crossing, Splatoon, Pokémon, Mario Party and most local co-op) works between friends' Macs over the internet. The game thinks everyone is in the same room. Nintendo's online service is never used or contacted, and nothing here works with real Switch consoles.

## For players

1. Get the **friends pass** from whoever set up your circle (they press **Send to a Friend…** in Docked › Settings › Friends; AirDrop and Messages save it in Downloads), then press **Add Friends Pass…** there.
2. In a game's **Game Settings**, switch on **Play with friends**.
3. Start the game, open its Friends screen (the Friends menu in the menu bar, or press both sticks in) to see your code and add your friends' codes, then use the game's own local wireless mode (for Smash: Local Wireless; Mario Kart: Wireless Play).

Games converted before this version of Docked need **Convert Again** to get the switch.

**Smooth play:** use Ethernet if you can. On Wi-Fi only, Docked offers to pause AirDrop and Handoff (the `awdl0` radio, which steps away from your network many times a second) until the game closes; it asks for your password once per game and can remember your choice. **Connection smoothing** is Off by default, so nothing is held back; for relaxed games (Animal Crossing) Medium can even out a bumpy connection. Both Macs must hold full speed, because each waits for the other: on a slower Mac, set Upscaling to Standard.

Friends you play with see your Mac's internet address, as with any game played directly between two computers. The pass lets anyone who has it into your circle, so send it privately.

## Starting a circle (once, by one person)

Needs a free Cloudflare account and an API token that can edit Workers (and, for the relay, Calls/TURN keys).

```
python3 -I Friends/meeting/setup_meeting.py
```

It puts a small meeting point on your own Cloudflare account (`worker.js`, `core.js`), saves your pass in `~/Library/Application Support/Docked/Friends/friends.cfg`, and never stores the token. Run it again to update the meeting point; `--new-key` replaces the circle's key (everyone then needs the new pass). The meeting point only introduces friends; game traffic goes directly between Macs, or through Cloudflare's TURN relay only when two Macs cannot reach each other.

## How it's built

`engine-patches/` are changes to the conversion engine (nxnative), applied by `apply.sh` on top of the reviewed engine in `ENGINE_PIN` whenever Docked packs an engine (`Bundle/make.sh`, `engine-release.sh`). They add a real `nn::ldn` (local wireless) on a virtual 169.254.77.0/24 network carried in one authenticated, encrypted UDP connection per friend, the meeting point client, NAT traversal (STUN, TURN) and the in-game Friends screen. Everything is off unless the game's `DM_FRIENDS` setting is on. The LDN record layouts follow switchbrew/libnx as collected in nxnative PR #846 (Robii Aragon, MIT).

Lag work (patches 0005 and 0007): lockstep games wait every frame for the other Mac, so any time a packet is held back is time both games stand still. Nothing is held back by default (the jitter cushion is a game setting, 0 to 25 ms), a packet from a friend goes to the game straight from the thread that received it instead of waking another thread first, two spare copies follow 3 and 10 ms later so a lost packet costs a few ms instead of a stall, and in a room the game log gets a line every 5 seconds with sent/received packets, spare copies, drops, and each friend's ping, worst ping and cushion. Tunables: `DM_FRIENDS_CUSHION_MS` (0 to 25, the game setting), `DM_FRIENDS_COPIES` (0 to 2), `DM_FRIENDS_TRACE=1` (calls, no names or addresses).

**Direct paths (patch 0008):** besides STUN, the link asks the home router for a port mapping (NAT-PMP, which PCP routers also answer), as Tailscale and game consoles do, so two homes behind strict routers can still connect directly instead of through the relay. Routers with it turned off simply don't answer.

**Engine updates:** `bump-engine.sh` stops before changing anything when the patches no longer apply. To refresh them: check out the new engine, `git am` the patches, fix what conflicts, then `git format-patch <new pin>..HEAD -o Friends/engine-patches` and update `engine-patches/BASE`.

**Tests:** in an engine checkout with the patches applied, the friends tests live in `dm/host/tests` (`t_friends_link.c`, `t_friends_net.c`, `t_friends_path.c`, `t_friends_internet.py`); the meeting point's own test is `node Friends/meeting/test/run.mjs`.
