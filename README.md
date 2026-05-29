# Kitty Hub

A Murder Mystery 2 script with ESP (boxes, names, roles, chams), gun ESP, auto aim, auto shoot, noclip, and movment hacks.

## Features

- **ESP** — Boxes, names, and role labels for all players
- **Chams** — Always-on-top highlights colored by role (red = murderer, blue = sheriff, green = innocent)
- **Gun ESP** — Highlights dropped guns on the ground
- **Auto Aim** — Press `C` (configurable) to equip your gun, find the murderer, and shoot (works off-screen)
- **Auto Shoot** — Automatically fires at the murderer every 0.5s (toggleable)
- **Noclip** — Walk through walls, toggle with `N`
- **Speed Hacks** — Move faster or slower (can be customizable)
- **Jump Hacks** — Jump higher or lower (can be customizable)

## Controls (defaults, can be customizable)

| Key | Action |
|---|---|
| `C` | Auto aim & shoot murderer (changeable in settings) |
| `N` | Toggle noclip |
| `X` | Toggle GUI |

## How to Use

1. Download `kittyhub.lua`.
2. Serve it locally:
   - **[Python 3](https://www.python.org/downloads/):** `python -m http.server 8000`
   - **[Node.js](https://nodejs.org/):** `npx http-server`
3. Use the URL `http://localhost:8000/kittyhub.lua` with your Roblox executor's `loadstring`.

## Configuration

Change settings via the GUI toggles or edit `CatSettings` at the top of the script:

```lua
getgenv().CatSettings = {
    Aimbot = {
        AutoShoot = true,
        AimbotKey = "C"   -- change to any Enum.KeyCode name
    }
}
```

## Credits
**Me** for putting this all together
**AetherHub** for ideas
