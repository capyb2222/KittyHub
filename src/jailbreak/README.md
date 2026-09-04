# Jailbreak

PlaceId 606849621. Builds to `jailbreak.lua`.

## Features

- **Auto rob** — takes whatever is open, flies there, loots it, banks the bag, repeats
- **Instant interactions** — the hold-to-use circle finishes straight away
- **Arrest all** — goes to every criminal in the server, then puts you back where you were
- **Arrest aura** — cuffs whoever comes near, without moving you
- **Robbery states**
- **Item farm**
- **Manual farm** — works the spot you are standing in and never moves you
- **Interact aura**
- **Travel** — every base and landmark in a dropdown
- **ESP**
- **Movements** — including safe landing, so flying down does not kill you
- **Visuals**
- **Config profiles**

## Your executor decides how much of this you get

Most of the list needs Jailbreak's own client modules, which means the executor
has to hand back real Lua objects from `getgc`. Plenty of them don't — Xeno
says it has the functions and returns nothing. Without them the game's
anti-cheat also stays on, and anything that moves you gets reverted.

**Settings → Executor Verdict** says which one you have. When it can't reach
them, the controls that cannot work are hidden rather than left there looking
fine, and you keep the robbery board, ESP, item farm, manual farm, anti-AFK,
the arrest aura and the whole Movement tab.

Noclip is the odd one out: it does switch your collisions off on any executor,
but with the anti-cheat still on the game puts you back on the wrong side of
the wall a moment later. That is the pull-back, not a broken toggle, and the
Movement tab says so when `getgc` is missing. Everything else on that tab is
plain client physics and works regardless — speed, jump, bhop, fly, spinbot.

**Manual farm** (Farm tab, `G`) is the answer to all of that. It never moves
the character, so there is nothing for the anti-cheat to reject: you drive to a
robbery yourself, park inside it, and it holds the game's own interact key so
the hold-to-rob circle fills, and touches the loot within reach. It is the only
farm that still earns anything on an executor that cannot reach the modules.

Check sUNC, not UNC — UNC counts functions that exist, sUNC counts ones that
work. Xeno is 40%. Anything near 100% is fine.

Xeno often will not attach here either. Join MM2 instead, run the loadstring,
then Settings → Switch Game → Jailbreak. It queues itself over the teleport.

It flies instead of teleporting, because Jailbreak does not like big jumps. Turn the
speed down in Travel if you get pulled back.

Jailbreak has its own fall damage and reads it off how fast you arrive, so flight is
safe right up until it stops. **Safe Landing** (Movement → Falling, on by default)
flies you down instead of dropping you when you switch fly off in the air, brakes a
dive before it reaches the ground, and slows any long fall you did not plan.

Hold handcuffs before an arrest sweep, or put the slot number in the Police tab and it
presses the key for you.

## Keys

| Key | |
|---|---|
| `X` | menu |
| `H` | arrest everyone |
| `N` | noclip |
| `F` | fly (WASD, space up, shift down) |
| `G` | manual farm |

Rebindable in the menu.
