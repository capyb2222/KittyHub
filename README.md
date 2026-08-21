# Kitty Hub

A Murder Mystery 2 script with a native Roblox UI — no Drawing API, no key system,
no loader ads. Built and tested against [Xeno](https://xeno.now/).

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

---

## Why this one

Most MM2 scripts guess at roles by looking for a knife in someone's backpack, which
means they know nothing until the murderer draws it. Kitty Hub reads the game's own
role table, so it names the murderer and the sheriff the instant a round starts.

Everything else follows from that: the aimbot knows who to shoot before you do, the
ESP is coloured correctly from the first second, and the proximity alert can warn
you about a murderer you have never seen.

It also cleans up after itself. Unloading restores lighting, collisions, transparency,
walk speed and camera — the game looks untouched afterwards.

---

## Features

### Aimbot
Press the key and the gun comes out, the murderer gets shot, and the gun stays out.
That's the whole interaction — **your mouse never moves and nothing needs to be on
screen**.

That works because MM2's gun is server-authoritative: the shot is a `RemoteFunction`
carrying a world position, and the server decides what it hit. Aiming means *sending
good coordinates*, not pointing a camera. So there is deliberately **no line-of-sight
check and no range limit** — the murderer can be behind a wall on the far side of the
map and the shot still lands. Prediction is what decides whether you hit, not
visibility.

| | |
|---|---|
| **Targeting** | Murderer (default), Nearest, or closest to crosshair |
| **Trigger** | Hold a key, toggle it, or fire continuously |
| **Auto equip** | Draws the gun if it is stowed, then waits for the server to register it before firing |
| **Keep equipped** | Re-draws the gun after a respawn or round change |
| **Prediction** | Velocity lead with damped vertical component, tunable 0–8 studs |
| **Ping compensation** | Scales the lead by your measured round trip |
| **Silent aim** | Redirects the shots *you* fire by hand — needs `hookmetamethod` |
| **Kill All** | Fires at every living player, paced so the server does not drop them |

### Knife (murderer)
Auto throw with prediction, knife aura with a radius, teleport-stab that blinks
back to where you were, and a target filter that can prioritise or avoid the sheriff.

### ESP
Corner or full boxes, names, role labels, distance, health bars, tracers, chams,
and off-screen edge arrows that point at players behind you. Per-role colour pickers.
World markers for coins, the dropped gun, and the murderer's traps — traps are
invisible in-game and are forced visible here.

### Farm
Coin farming with three travel modes (teleport / interpolated / walk), plus a coin
**magnet** that fires touch events on nearby coins without moving you at all —
slower, but it stacks with playing normally. Auto-grabs the dropped gun the moment
a sheriff dies and snaps back to where you were standing.

### Safety
The half of an MM2 script that keeps you alive as an innocent:

- **Proximity alert** — red screen-edge vignette that intensifies as the murderer
  closes in, with a beep that speeds up with proximity
- **Auto dodge** — launches you clear if the knife gets too close (disabled while
  you are armed, since bailing out is worse than shooting back)
- **Role reveal** — names the murderer and sheriff as soon as roles are dealt

### Movement
Walk speed (humanoid or CFrame-driven), jump power, infinite jump, bunny hop,
noclip, fly, spinbot. Teleports to the murderer, sheriff, dropped gun, nearest coin,
lobby, or a random spawn. Named waypoints saved to disk.

### Visuals
Fullbright, fog removal, custom FOV, x-ray walls that leave players and pickups
solid, and a low-detail mode that disables particles, trails and shadows.

### Players
Live roster with role colours, distance and alive state. Click a name to spectate,
click the arrow to teleport.

### Interface
Searchable menu, drag-to-move window, live accent recolouring via an HSV picker
built from gradients (no image assets), toast notifications, a watermark with
FPS / ping / role / round timer, an on-screen keybind list, and named config
profiles saved to `KittyHub/configs/`.

---

## Keybinds

| Key | Action |
|---|---|
| `X` | Toggle menu |
| `C` | Aim (hold) or arm the aimbot (toggle mode) |
| `N` | Noclip |
| `F` | Fly — `WASD` to move, `Space` up, `Left Shift` down |

All rebindable in-game; the on-screen list shows the current bindings and lights up
when a feature is active.

---

## Running it

```bash
git clone https://github.com/capyb2222/mm2-script.git
cd mm2-script
python localhost.py
```

Then in your executor:

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

The dev server rebuilds `mm2.lua` from `src/` whenever the sources change, so the
loop is just *save, re-execute in Roblox*. Useful flags:

```bash
python localhost.py 8080        # different port
python localhost.py --lan       # also reachable from a phone on the same network
python localhost.py --no-build  # serve as-is, never rebuild
```

Re-running the loadstring is always safe — the script unloads its previous instance
before building a new one.

---

## Project layout

`mm2.lua` ships as one file because executors run a single chunk from a single HTTP
request. It is **generated** — the real sources are split under `src/mm2/` and
concatenated by `build.py`.

```
src/mm2/
  01_prelude.lua      services, shared namespace, lifecycle + error damping
  02_config.lua       defaults schema, deep-merge, on-disk profiles
  03_util.lua         maths, projection, line of sight, prediction
  04_game.lua         everything MM2-specific: roles, remotes, map, coins
  05_ui_core.lua      window shell, tabs, notifications, watermark, theming
  06_ui_controls.lua  toggle, slider, dropdown, keybind, button, input, colour
  07_esp.lua          player drawings + world markers
  08_combat.lua       aimbot, silent aim, knife tooling
  09_farm.lua         coins, magnet, gun grabbing, anti-AFK
  10_safety.lua       proximity warning, auto-dodge, announcements
  11_movement.lua     speed, noclip, fly, teleports, waypoints
  12_visuals.lua      lighting, FOV, x-ray, detail stripping
  13_menu.lua         every tab and control
  14_main.lua         hotkeys, the single render loop, unload
```

```bash
python build.py mm2           # rebuild mm2.lua
python build.py --check       # rebuild everything and syntax-check it
npm install && npm run check  # syntax-check the built files directly
```

Two design constraints worth knowing before editing:

- **One render loop.** Features register per-frame work with `KH.onFrame(name, fn, order)`
  instead of opening their own connection. Each job is `pcall`-wrapped, so a broken
  feature cannot take the menu down with it — and **nothing in a frame job may yield**.
- **Locals are scoped.** A Lua chunk's main body is capped at 200 active locals, and
  the build concatenates fourteen files into one chunk. Module bodies are wrapped in
  `do ... end` and export through the shared `KH` table.

---

## What the script knows about MM2

Documenting this because it is the part that actually took research, and it is what
breaks when the game updates.

| Thing | Where it lives |
|---|---|
| Role table | `ReplicatedStorage.GetPlayerData:InvokeServer()` → `{[name] = {Role, Killed, Dead}}` |
| Live role push | `ReplicatedStorage.Remotes.Gameplay.PlayerDataChanged.OnClientEvent` |
| Shoot | `Character.Gun.KnifeLocal.CreateBeam.RemoteFunction:InvokeServer(1, position, "AH2")` |
| Stab | `Character.Knife.Stab:FireServer("Down")` |
| Throw | `Character.Knife.Events.KnifeThrown:FireServer(fromCFrame, toCFrame)` |
| Map | the `workspace` child owning both `CoinContainer` and `Spawns` |
| Coins | children of `CoinContainer` — either a `BasePart` or a model wrapping `CoinVisual.MainCoin` |
| Dropped gun | a `BasePart` named `GunDrop`, parented into the map when a sheriff dies |
| Round timer | `workspace.RoundTimerPart:GetAttribute("Time")` |

Remotes are resolved by recursive name lookup rather than a fixed path, and the shot
tag falls back from `"AH2"` to `"AH"` if the server rejects it — both so a game update
degrades instead of breaking outright. Every feature has a tool-sniffing fallback for
when the role remote is unavailable.

---

## Compatibility

Needs an executor that exposes `gethui()` or `CoreGui`. Everything else is
feature-detected and degrades:

| API | Without it |
|---|---|
| `writefile` / `makefolder` | settings live only until Roblox closes |
| `hookmetamethod` | silent aim is unavailable; the aimbot still works |
| `firetouchinterest` | coin farm can travel but not collect |

Tested on Xeno.

---

## Other modules

`generic.lua` is the fallback for any other game and is still on the old Drawing-API
build — it was left alone deliberately, since this pass was MM2-only.

---

## Credits

- capyb2222
- Structure and remote names cross-checked against several open-source MM2 scripts
  and YARHM.
