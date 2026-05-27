# Kitty Hub

A Murder Mystery 2 script with ESP (boxes, names, roles, chams), gun ESP, auto aim, auto shoot, and noclip.

## Features

- **ESP** — Boxes, names, and role labels for all players
- **Chams** — Always-on-top highlights colored by role (red = murderer, blue = sheriff, green = innocent)
- **Gun ESP** — Highlights dropped guns on the ground
- **Auto Aim** — Press `C` (configurable) to equip your gun, find the murderer, and shoot (works off-screen)
- **Auto Shoot** — Automatically fires at the murderer every 0.5s (toggleable)
- **Noclip** — Walk through walls, toggle with `N`

## Controls

| Key | Action |
|---|---|
| `C` | Auto aim & shoot murderer (changeable in settings) |
| `N` | Toggle noclip |
| `X` | Toggle GUI |

## How to Use

1. Download `aimbot_mm2.lua`.
2. Host it on a pastebin or local server.
3. Execute with your Roblox executor's loadstring.

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
