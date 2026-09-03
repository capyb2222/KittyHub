<p align="center">
  <img src="logo.png" alt="Kitty Hub" width="170">
</p>

<h1 align="center">Kitty Hub</h1>

<p align="center">Messy MM2 script. Many features are broken, so see what works for you.</p>


## Loadstring
- Paste this in your executor after you run your server (localhost.py)

```lua
loadstring(game:HttpGet("http://localhost:8000/kittyhub.lua"))()
```

## Features

- **Aimbot**
- **ESP**
- **World markers**
- **Coin farm** 
- **Murderer alert**
- **Auto dodge (?)**
- **Role reveal**
- **Murderer stuff**
- **Movements**
- **Teleports**
- **Visuals**
- **Players**
- **Config profiles**
- **And more!**

Silent aim might not work, so you can try the mouse one (it should work pretty well)

## Keys

| Key | |
|---|---|
| `X` | menu |
| `C` | aim and shoot |
| `N` | noclip |
| `F` | fly (WASD, space up, shift down) |
| `G` | throw the knife once, at the sheriff if one is in range (needs Auto Throw on) |

Rebindable in the menu.

## Running it

```bash
git clone https://github.com/capyb2222/mm2-script.git
cd mm2-script
python localhost.py
```

No Python? Use the PowerShell instead, it does the same thing, and Windows already has it:

```powershell
powershell -ExecutionPolicy Bypass -File localhost.ps1
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

Built and tested on [Xeno](https://xeno.now/). There are features implemented where Xeno does not support!

## Credits
- Me of course
- Various other scripts, mostly inspired by AetherHub and YARHM.