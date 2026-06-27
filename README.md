# Kitty Hub

A roblox script mainly for the game Murder Mystery 2.

## How It Works

`kittyhub.lua` is a thin dispatcher. It checks `game.PlaceId` and loads the right module:

| Game | PlaceId | Module |
|---|---|---|
| Murder Mystery 2 | `142823291` | `mm2.lua` |
| Anything else | — | `generic.lua` |

## Modules

### mm2.lua — Murder Mystery 2
Full features: ESP (boxes, names, roles, chams, tracers, distance), auto aim & shoot, prediction, FOV circle, gun ESP, auto-collect (teleport), noclip, speed/jump hacks, rainbow mode, crosshair (dot/cross/circle), spectator list.

### generic.lua — Any Game
Basic features: ESP (boxes, names, chams, tracers, distance), noclip, speed/jump hacks, fly (WASD + Space/Shift).

## How to Use

1. `git clone https://github.com/capyb2222/mm2-script.git`
2. `cd mm2-script`
3. Start a local server:
   - **Python 3:** `python -m http.server 8000` (or `localhost.py`)
   - **Node.js:** `npx http-server`
3. Execute in your executor:

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

## Compatibility

Works on most executors that support `getgenv()` or `_G`, `Drawing`, and `Instance.new("Highlight")`. If your executor lacks `getgenv()`, the script falls back to `_G` automatically.
Mainly tested on Xeno.

## Persistence

All settings are stored in `getgenv().CatSettings` and survive script re-runs.

## Credits
- capyb2222
- Many popular scripts like Aetherhub for ideas.