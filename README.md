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
Native Roblox UI (no Drawing API). Features:
- **Aimbot** — locks onto the murderer and fires your sheriff gun (auto-equips it). Hold-key or auto-shoot, with off-screen aim.
- **ESP** — boxes, names, roles, tracers, chams, distance (color-coded by role).
- **Gun ESP** — marks dropped guns in **yellow**.
- **Auto Collect** — teleports you onto the nearest dropped gun.
- **Noclip** (keybind), **Speed/Jump** hacks.

Open the menu with the **Kitty** button (bottom-left) or press **X**. Settings persist across re-runs via `getgenv().CatSettings`.

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
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua?v="..tostring(tick())))()
```

## Compatibility

Works on most executors that supports native Roblox UI.
Recommend Xeno since I mainly tested there.

## Persistence

All settings are stored in `getgenv().CatSettings` and survive script re-runs.

## Credits
- capyb2222
- Many popular scripts like Aetherhub for ideas.