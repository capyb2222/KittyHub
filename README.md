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
One press is one shot: it locks on, fires, and hands the camera straight back.

MM2's gun is server-authoritative: the shot is a `RemoteFunction` carrying a world
position, and the server decides what it hit. So target selection has deliberately
**no line-of-sight check and no range limit**. On the `Remote` fire method that holds
all the way through — the murderer can be behind a wall on the far side of the map and
the shot still lands. On `Mouse` the click is a client raycast, so a wall between you
and them stops it the way it stops everyone else.

| | |
|---|---|
| **Targeting** | Murderer (default), Nearest, or closest to crosshair |
| **Trigger** | `Press` (default) fires one shot per key press; or hold the key, toggle it, or fire continuously |
| **Auto equip** | Draws the gun if it is stowed, then waits for the server to register it before firing |
| **Keep equipped** | Re-draws the gun after a respawn or round change |
| **Prediction** | Velocity lead with damped vertical component, tunable 0–8 studs |
| **Ping compensation** | Scales the lead by your measured round trip |
| **Fire method** | `Mouse` (default) aims the real cursor and lets MM2 fire; `Remote` sends the shot itself — see below |
| **Silent aim** | Redirects the shots *you* fire by hand. Works without `hookmetamethod` — see below |
| **Kill All** | Fires at every living player, paced so the server does not drop them |

**Aimbot Status** on the same tab says in one line why nothing is being shot —
`waiting for C`, `no gun`, `no target`, or what the last shot did. An aimbot
that does nothing looks the same whether the key never registered, the gun is
not yours, or the shot is going out and the server is dropping it, and only the
last of those is worth changing the fire method over.

### Fire method
`Mouse` is the default. It builds no shot at all — it turns the camera onto the
target, drives the real cursor onto them, and clicks, so MM2's own gun script
fires the shot the way it does for a human. Nothing about it needs a hook, and
it works where a built shot is ignored. It needs the executor to expose
synthetic mouse input (`mousemoverel` / `mousemoveabs`, `mouse1press` /
`mouse1click`, or `VirtualInputManager`); **Mouse Control** on the Aimbot tab
names what it found, or says the executor has none. With **Turn Camera** on the
target does not have to be on screen — facing them is what puts them there, and
**Aim Speed** below 1 walks the cursor across instead of teleporting it.

Prediction does not apply on this route. The lead exists to cover a server-side
shot's flight and your ping; a client raycast has neither, so leading only walks
the ray off the target's body — worst on someone falling, whose downward
velocity drags the aim point below them.

The trade is visibility: this one moves your camera and your cursor, and anyone
spectating sees that.

`Remote` is the quiet one: the position goes straight to the server, your view
never moves and walls do not matter. It is strictly better **where the game
accepts it** — and where it does not, it fails silently, since the shot remote
answers the same either way. **Aimbot Status** showing `remote shot at <name>`
while nobody dies is what that looks like.

### Silent aim without a hook
Silent aim is normally gated behind `hookmetamethod`, which most free executors
either do not ship or ship as a stub that reports success and hooks nothing.
That gate is avoidable. MM2's gun never raycasts on the client: `KnifeLocal`
reads your mouse and hands the server a world position, and the server alone
decides what was hit — which is the same fact the aimbot already runs on.

So there are three routes, and Kitty Hub takes the best one the executor can
actually do. The **Silent Aim Route** dropdown forces one; **Route In Use** on
the same tab and in Settings → Session says which is live.

| Route | Needs | What happens |
|---|---|---|
| `hook` | a working `hookmetamethod`, or `getrawmetatable` + `setreadonly` | Your shot's position argument is rewritten in flight. Nothing else changes |
| `takeover` | the ability to set `Disabled` on a script — every executor | MM2's gun script is switched off on your client, so your click no longer produces a shot of its own, and Kitty Hub fires the aimed one from that same click. Still one shot, still on target. You lose the shot sound and muzzle flash your own client plays; the beam and the kill come from the server, so everyone including you still sees those |
| `click` | nothing | The old stand-in: your click fires an aimed shot *beside* your real one, so two beams go out |

Takeover and the `Mouse` fire method cannot both be on: the mouse aimbot fires
MM2's gun script and takeover switches that script off. With `Mouse` selected,
silent aim uses the hook if there is one and click aim otherwise, and **Route In
Use** says so.

The hook install is verified rather than trusted — it has to fire on a harmless
call before Auto will use it, which is what keeps a stubbed `hookmetamethod`
from silently selecting a route that does nothing. Everything the takeover
route touches is a client-side property write, so none of it replicates, and
turning the toggle off (or unloading) switches MM2's script back on and
re-draws the gun so it re-initialises.

`can_silent_aim.lua` in the repo root reports all three routes for an executor
without loading the rest of the script.

### Knife (murderer)
Auto throw with prediction, knife aura with a radius, teleport-stab that blinks
back to where you were, and a target filter that can prioritise or avoid the sheriff.

Throwing and blinking both have a range: a knife thrown further than it can reach
just leaves you unarmed until it returns, and crossing the map to stab someone is
a teleport everyone sees rather than a stab. Anyone already within swinging
distance is stabbed where they stand instead of being blinked to.

Auto grab of the dropped gun never fires when you are the murderer — you cannot
pick it up, so it would only teleport you onto the sheriff's body seconds after
killing them and stand there until the pickup timed out.

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
| `C` | One lock-and-shot at the murderer. Other triggers: hold to keep firing, toggle to stay locked on, or always-on |
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
| `hookmetamethod` | falls back to `getrawmetatable` + `setreadonly`, then to click aim. Xeno 1.3.60 has neither hook — and its `hookfunction` is a stub that reports success without hooking — so it runs click aim |
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
