# Kitty Hub

MM2 script with a native Roblox UI. No Drawing API, no key system, no ads.

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

## Features

- **Aimbot** — press `C`, it locks onto the murderer, fires once, gives the camera back
- **ESP** — boxes, names, roles, distance, health, tracers, chams, off-screen arrows
- **World markers** — coins, the dropped gun, and the murderer's traps
- **Coin farm** — teleport, smooth or walk, plus a magnet that grabs coins near you
- **Murderer alert** — screen vignette and a beep that speed up as they get closer
- **Auto dodge** — jumps you clear when the knife gets too close
- **Role reveal** — names the murderer and sheriff the moment roles are dealt
- **Knife** — auto throw, stab aura, teleport stab, sheriff filter
- **Movement** — speed, jump, infinite jump, bunny hop, noclip, fly, spinbot
- **Teleports** — murderer, sheriff, gun, coin, lobby, plus saved waypoints
- **Visuals** — fullbright, no fog, FOV, x-ray walls, low detail
- **Players** — roster with roles, click to spectate or teleport
- **Config profiles** saved to disk

Silent aim, Kill All and the `Remote` fire method need an executor the game accepts
built remote calls from. They do nothing on Xeno.

## Keys

| Key | |
|---|---|
| `X` | menu |
| `C` | aim and shoot |
| `N` | noclip |
| `F` | fly (WASD, space up, shift down) |

Rebindable in the menu.

## Running it

```bash
git clone https://github.com/capyb2222/mm2-script.git
cd mm2-script
python localhost.py
```

Run the loadstring above. It rebuilds when sources change, so just save and re-execute.
Re-running unloads the old copy first.

## Editing it

`mm2.lua` is generated. Sources are in `src/mm2/`, joined by `build.py`.

```bash
python build.py mm2      # rebuild
python build.py --check  # rebuild and syntax check
```

Per-frame features go through `KH.onFrame` and must not yield. Module bodies are wrapped
in `do ... end` for the 200 local limit.

Built and tested on [Xeno](https://xeno.now/).
