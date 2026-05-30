# Kitty Hub v3

A Murder Mystery 2 script with a polished AetherHub-style tabbed GUI, full ESP suite, aim assist, and quality-of-life features.

## Features

### ESP Tab
- **Boxes** — 2D bounding boxes around each player
- **Names** — Player name labels (with optional distance display)
- **Roles** — Role text (Murderer, Sheriff, Innocent) below each player
- **Chams** — Always-on-top highlights colored by role (red / blue / green)
- **Tracers** — Role-colored lines from screen bottom to each player
- **Distance** — Appends `[~NN]` to name labels

### Aimbot Tab
- **Auto Shoot** — Automatically fires at the murderer
- **Prediction** — Leads shots based on target velocity
- **FOV Circle** — Visual aim radius on screen
- **Off-Screen Aim** — Aim at murderers even when not on screen
- **FOV Radius** — Slider (50–400px)

### MM2 Tab
- **Gun ESP** — Highlights dropped `GunDrop` objects with gold text
- **Noclip** — Walk through walls (toggle with `N`)
- **Auto Collect** — Teleports to the nearest dropped gun and auto-equips

### Movement Tab
- **Speed Hack** — Walk speed override (16–100, slider)
- **Jump Hack** — Jump power override (50–200, slider)

### Visuals Tab
- **Rainbow Mode** — Cycles all accent colors through HSV (speed slider 0.5–5)
- **Crosshair** — Dot, Cross, or Circle style (size/thickness sliders)

### Misc Tab
- **Spectator List** — Overlay showing which players are watching you

## Controls

| Key | Action |
|---|---|
| `X` | Toggle GUI |
| `N` | Toggle noclip |
| `C` | Manual aim & shoot murderer (configurable) |

## How to Use

1. Download `kittyhub.lua`.
2. Serve it locally:
   - **Python 3:** `python -m http.server 8000` (or `localhost.py`)
   - **Node.js:** `npx http-server`
3. Use `loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()` in your executor.

## Persistence

All settings are stored in `getgenv().CatSettings` so they survive script re-runs.

## Credits
**Me** for putting this all together

**AetherHub** for ideas
