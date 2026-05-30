# Kitty Hub

A universal Roblox script with auto-detecting game support. One loadstring works across games.

## How It Works

`kittyhub.lua` is a thin dispatcher. It checks `game.PlaceId` and loads the right module:

| Game | PlaceId | Module |
|---|---|---|
| Murder Mystery 2 | `142823291` | `mm2.lua` |
| Anything else | — | `generic.lua` |

## Modules

### mm2.lua — Murder Mystery 2
Full feature set: ESP (boxes, names, roles, chams, tracers, distance), auto aim & shoot, prediction, FOV circle, gun ESP, auto-collect (teleport), noclip, speed/jump hacks, rainbow mode, crosshair (dot/cross/circle), spectator list.

### generic.lua — Any Game
Basic features: ESP (boxes, names, chams, tracers, distance), noclip, speed/jump hacks, fly (WASD + Space/Shift).

## Controls

| Key | Action |
|---|---|
| `X` | Toggle GUI |
| `N` | Toggle noclip |
| `F` | Toggle fly (generic only) |
| `C` | Manual aim & shoot murderer (mm2 only) |

## How to Use

1. Download all files from the repository or serve them locally.
2. Start a local server:
   - **Python 3:** `python -m http.server 8000` (or `localhost.py`)
   - **Node.js:** `npx http-server`
3. Execute in your executor:

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

## Compatibility

Works on most executors that support `getgenv()` or `_G`, `Drawing`, and `Instance.new("Highlight")`. If your executor lacks `getgenv()`, the script falls back to `_G` automatically.

## Persistence

All settings are stored in `getgenv().CatSettings` and survive script re-runs.