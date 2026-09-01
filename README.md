# Kitty Hub

An MM2 script with a normal Roblox UI. No Drawing API, no key system, no loader ads.

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

Roles come from the game's own role table, so it knows who the murderer is the moment
the round starts instead of waiting for them to pull the knife out. Unloading puts
lighting, collisions, walk speed and your camera back the way they were.

## What's in it

**Aimbot.** Press `C` and it locks onto the murderer, fires once, and gives your camera
back. Two ways to shoot: `Mouse` (the default) drives your real cursor and lets MM2's own
gun fire, `Remote` sends the shot straight to the server. Remote is the better one where
it works, since it's silent and goes through walls, but plenty of executors can't use it.
If nothing's dying, the Aimbot Status line on the tab tells you why.

**Silent aim.** Puts the shots you fire by hand on the target. Doesn't need
`hookmetamethod`: with no hook it switches MM2's gun script off and fires the aimed shot
from your click instead. Run `can_silent_aim.lua` to see what your executor can manage.

**Knife.** Auto throw, stab aura, teleport stab, and a filter for going after the sheriff
first or leaving them alone. Throwing and blinking both have a range limit so you don't
launch your knife across the map or teleport somewhere obvious.

**ESP.** Boxes, names, roles, distance, health, tracers, chams, and arrows for players
behind you. Markers for coins, the dropped gun, and the murderer's traps, which are
invisible in game.

**Farm.** Coin farming by teleport, smooth hop or walking, plus a magnet that collects
coins near you without moving at all. Picks up the dropped gun when a sheriff dies.

**Safety.** Red screen edges and a beep that speed up as the murderer closes in, auto
dodge, and role announcements as soon as they're dealt.

**Movement.** Speed, jump, infinite jump, bunny hop, noclip, fly, spinbot, teleports,
saved waypoints.

**Visuals.** Fullbright, no fog, custom FOV, x-ray walls, low detail mode.

## Keys

| Key | |
|---|---|
| `X` | menu |
| `C` | aim and shoot |
| `N` | noclip |
| `F` | fly (WASD, space up, shift down) |

All rebindable in the menu.

## Running it

```bash
git clone https://github.com/capyb2222/mm2-script.git
cd mm2-script
python localhost.py
```

Then run the loadstring above. The server rebuilds `mm2.lua` when the sources change, so
it's just save and re-execute in Roblox. Re-running is always safe, it unloads the old
copy first. `python localhost.py 8080` for another port, `--lan` to reach it from a phone.

## Editing it

`mm2.lua` is generated, don't edit it. The real sources are in `src/mm2/`, one file per
area, glued together by `build.py` because executors only run a single file.

```bash
python build.py mm2      # rebuild
python build.py --check  # rebuild and syntax check
```

Two things to know first. Per-frame features register with `KH.onFrame` instead of opening
their own RenderStepped connection, and they must not yield. Module bodies are wrapped in
`do ... end` because one Lua chunk only gets 200 locals and this is fourteen files in one.

## Executors

Built and tested on [Xeno](https://xeno.now/). Needs `gethui()` or CoreGui, everything
else is optional and degrades quietly: no `writefile` means settings don't survive a
restart, no `firetouchinterest` means the coin farm can travel but not collect, no working
`hookmetamethod` means silent aim uses one of the fallbacks above.

`generic.lua` is an old fallback for other games and hasn't been touched in a while.

## Credits

capyb2222. Remote names cross-checked against various open-source MM2 scripts and YARHM.
