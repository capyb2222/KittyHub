# Jailbreak

PlaceId 606849621. Builds to `jailbreak.lua`.

## Features

- **Auto rob** — takes whatever is open, flies there, loots it, banks the bag, repeats
- **Instant interactions** — the hold-to-use circle finishes straight away
- **Arrest all** — goes to every criminal in the server, then puts you back where you were
- **Arrest aura** — cuffs whoever comes near, without moving you
- **Robbery states**
- **Item farm**
- **Interact aura**
- **Travel** — every base and landmark in a dropdown
- **ESP**
- **Movements**
- **Visuals**
- **Config profiles**

## Your executor decides how much of this you get

Most of the list needs Jailbreak's own client modules, which means the executor
has to hand back real Lua objects from `getgc`. Plenty of them don't — Xeno
says it has the functions and returns nothing. Without them the game's
anti-cheat also stays on, and anything that moves you gets reverted.

**Settings → Executor Verdict** says which one you have. When it can't reach
them, the tabs that cannot work are hidden rather than left there looking fine,
and you keep the robbery board, ESP, anti-AFK and the arrest aura.

Check sUNC, not UNC — UNC counts functions that exist, sUNC counts ones that
work. Xeno is 40%. Anything near 100% is fine.

Xeno often will not attach here either. Join MM2 instead, run the loadstring,
then Settings → Switch Game → Jailbreak. It queues itself over the teleport.

It flies instead of teleporting, because Jailbreak does not like big jumps. Turn the
speed down in Travel if you get pulled back.

Hold handcuffs before an arrest sweep, or put the slot number in the Police tab and it
presses the key for you.

## Keys

| Key | |
|---|---|
| `X` | menu |
| `H` | arrest everyone |
| `N` | noclip |
| `F` | fly (WASD, space up, shift down) |

Rebindable in the menu.
