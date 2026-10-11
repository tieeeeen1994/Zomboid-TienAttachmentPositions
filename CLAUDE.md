# Tien's Attachment Positions

Project Zomboid B42 mod: each player moves, turns and resizes the spots their attached items hang from (belt, holsters,
back, every slot a bag or attachment mod adds), and every other player sees it. The live code is under
`Contents/mods/TienAttachmentPositions/42/`. General engine findings go in
`~/Zomboid/Workshop/ZomboidFixesB42/CLAUDE.md` ("Attached item models and attachment points (42.21)" holds the ones
this mod rests on); this file only holds the reasoning behind this mod.

The Lua source has no comments on purpose. Non-obvious reasoning lives here; update this file when it changes.

## Status

First implementation, 2026-10-11, **not yet run in game**. Logic tested in a real Lua against mocks of the Java side
(`scripts/test`, see below): single player, and a server with three clients exchanging commands and attach packets.
Things to verify are listed under "To verify".

## How it works

An attached item hangs from a **location** (`AttachedLocations.getGroup("Human")`, e.g. `Belt Left`), which names an
**attachment point** on the body ModelScript (`belt_left` on `Base.FemaleBody` / `Base.MaleBody`). The point is one per
model script for the whole game, so moving it moves every character (what Plysken's Adjust Attachment does, locally).
The renderer looks the point up by name per character every frame, and the location name of each attach reaches
everyone in `GameCharacterAttachedItemPacket`. So each player who adjusts a point gets copies:

- id `ns` per username (server-assigned "1", "2"...; usernames are forename+surname in single player, so per character
  there).
- point copy `<point>@<ns>` on every model script that has the point (`ScriptManager:getAllModelScripts()`, indexed
  once per world): body scripts get factory + the player's delta (offset added, rotation added in degrees, scale
  multiplied); every other script (item models) gets an unchanged copy, because `addStatic(parent, model, name, name)`
  also looks up the item model's **own** attachment of that name (Plysken's masks and tents fine-tune themselves that
  way), so without it those items would lose their own offset on a copy.
- A body script is recognised **as an object** (`Core.IsBody`, a table keyed by the ModelScript):
  `getScriptManager():getModelScript("FemaleBody")` / `("MaleBody")` (looked up by the bucket's map key), plus
  whatever `chr:getHumanVisual():getModelScript()` returns for a player seen (`HumanVisual.getModelScript`:
  `forceModelScript` or FemaleBody / MaleBody by sex; `Core.NoteBody`, which re-applies every copy when it learns a new
  one). Factory values are keyed by the script object too. Never by `isStatic()` or `getName()`: model scripts load
  with `ResetExisting`, so every further `model FemaleBody` block (Plysken, KATTAJ1 and other attachment mods add their
  points that way) calls `reset()` first, which sets `isStatic` back to true **and `name` to null** (only
  `InitLoadPP`, at parse time, sets it; attachments survive). With Plysken loaded the bodies report static and
  `getName()` is nil. 0.1.0 checked the flag and 0.1.1 the name, so on the server tests of 2026-10-11 every spot was
  greyed out ("no point on the model"). Each world load logs `[TienAttachmentPositions] model scripts with points: N,
  bodies: 2, body points: M`; bodies 0 means this went wrong again.
- location copy `<location>@<ns>` for **every** location whose attachment name is the point (vanilla has several
  locations per point), pointing at the point copy.

Copies are never removed: saved characters and corpses may name them. A reset point keeps its copies at factory
values and its items move back to the base location. Factory values are read the first time a point is copied; with
Plysken loaded, its `PAR_AttachCalibrate.factoryPoints` win (it may already have moved the base point).

### The wrappers

`IsoPlayer`'s class `__index` table (Kahlua: one table per class, chained to the superclass's by metatable, so setting
a key on `IsoPlayer`'s shadows `IsoGameCharacter`'s for players only; zombies untouched, `IsoAnimal` skipped by
`instanceof`) gets two wrappers, originals kept in `index.TienAttachmentPositions_Originals` so a reload never wraps
twice:

- `setAttachedItem(loc, item)` (client: local players; server: every player): with an item, attaches to the player's
  copy when they have values for that point, else to the base, after emptying the other variant (two packets: one
  clearing, one attaching; the remote client's copy of a moved item is a fresh object, so Java's own
  "remove the item from its old location" would not find it there). With `nil`, detaches where the item really is.
- `getAttachedItem(loc)` (every player): a base name finds the item on that player's copy. **Essential**: vanilla
  `ISHotbar:update` re-attaches every frame any item for which `getAttachedItem(item:getAttachedToModel())` is nil,
  and `ISAttachItemHotbar:stop` compares with it.

The item's own `attachedToModel` keeps the base name (only `setAttachedItem`'s location is swapped), so every slot
mod's hotbar logic keeps seeing the names it knows. That is also why removing the mod is clean: an item whose saved
location is unknown is skipped on load, and the hotbar re-attaches it from `attachedToModel`.

Java-side attaches (packet handlers, loading) never go through the wrappers; all player attaches in vanilla and
the slot mods start in Lua.

### Ordering

A client must know `<location>@<ns>` before an attach naming it arrives (`AttachedItems.setItem` → `checkValid`
throws there; loading skips it instead). So:

- The owner only uses a copy once the server's broadcast `pt` registered it on its own client (sent to everyone at the
  same time), and the server registers before broadcasting (`processServer` checks too).
- A client joining sends `hello`; the server answers `all` and sends `resend` to every other online player with
  copies, whose clients re-send their copy attaches (`Core.Resend`), so the joiner sees them even if it loaded those
  players before `all` arrived.
- After every `all` / `pt`, each local player is normalized (`Core.Normalize`): items moved to the copy or back to
  the base. That also fixes the owner's own items, which its client skipped on load (data arrives after the player).

### Protocol (module `TienAttachmentPositions`)

Client → server: `hello`, `set {p, v, seq}` (v nil or identity = reset), `resetAll`. Server → client: `all {ids, reg,
pts}`, `pt {u, n, p, v, seq}` (to everyone), `resend` (to one player). Single player calls the other side's handler
directly (`Core.ToServer` / `ToClient`; `sendServerCommand` does nothing there).

Server checks: the point must be a known attachment name of a base location (from the group), not `head_hat` /
`bowtie` (Java never sends those), no `@` or `:`, not a body location name (`Core.Adjustable`), at most 300 points a
player; values clamped (move ±0.5, turn ±180, size 0.25-3, rounded to 0.001).

Store: global mod data `TienAttachmentPositions` = `{ ids = {user = ns}, next, reg = {ns = {point = true}},
pts = {ns = {point = {ox, oy, oz, rx, ry, rz, s}}} }` (string keys everywhere).

### Live editing

The window sends at most every 150 ms (`Client.SEND_MS`, flushed on close) and applies each slider move to its own
copy at once. Each edit has a sequence number per user and point; an echo older than the latest local edit is
registered but its values are ignored, so the slider is never pulled back while dragging.

### Clothing-hidden points

`ModelManager` hides an attached item when `ItemBodyLocation.get(ResourceLocation.of(attachmentName))` is a body
location some worn item hides. Vanilla's `ShoulderHolster` and `AnkleHolster` points share their name with body
locations; a copy (`shoulderholster@3`) would lose that, so those points are not adjustable (greyed with a reason).

### Plysken Attachments Reborn

`PAR_AttachCalibrate.applyAll` is replaced by a no-op and `restoreFactory()` is called (at load and on
`OnGameStart`), its context menu handler is removed, and its window closed. Its base-point overrides were per computer
and moved a spot for every character on that screen, which would make players look different to each other.

## Files

- `shared/TienAttachmentPositions_Core.lua`: names, clamping, registry (`Register`, `ApplyValues`, `RegisterAll`,
  `ResetWorld` on each world load since scripts are reloaded), the wrappers, `Normalize` / `Resend`, transport.
- `server/TienAttachmentPositions_Server.lua`: store, `OnInitGlobalModData` registration (before players load, so
  saved copy locations stay attached on the server), command handler.
- `client/TienAttachmentPositions_Client.lua`: command handler, local edits, context menu (`OnFillInventoryObjectContextMenu`,
  which the hotbar's right-click menu fires too), Plysken switch-off, `hello` on `OnGameStart`.
- `client/TienAttachmentPositions_Window.lua`: the window. Everything is measured from the font
  (`getFontHeight`, `MeasureStringX`): label column = widest label, value column = "-180.000", sliders 12 font heights
  (shrunk to fit the screen width, at least 100), heading and note word-wrapped, buttons sized to their text and
  wrapped onto more rows when needed, the note dropped when the window would be taller than the screen.

## Tests

`scripts/test`: `mock.lua` imitates the Java side (location group with `checkValid`, model scripts, class
metatables, players, commands); `run.py` runs single player and a server with three clients, routing commands and
attach packets the way the game does (Java-side attaches call the original method, not the wrapper); `win.py` builds
the window at several font and screen sizes and checks for overflow and overlaps. Needs lupa:
`py -m pip install --target <dir> lupa`, then `LUPA_PATH=<dir> py -I scripts/test/run.py` (and `win.py`).

## To verify

1. The wrappers catch vanilla's hotbar attach (no "[TienAttachmentPositions] ... not reachable" in the log; moving a
   slider moves the item).
2. A slider moves the item live, without re-attaching (the renderer reads the point every frame).
3. Size works on a body point (`makeAttachmentTransform` scales by the point's scale).
4. `ModelAttachment.new(id)` and `ModelScript:addAttachment` from Lua.
5. Two players: each sees the other's change live; a third joining later sees both; relog and server restart keep it.
6. Plysken: its masks and tents still sit right on a moved spot (item self points); its menu option is gone.
7. Two locations sharing one point (vanilla `Belt Left` / `Belt Left Upside` style) both follow.
8. Death: the corpse and the zombie keep the items where they were.
9. Dedicated server log: no errors from the server file at start (it never touches model scripts).
