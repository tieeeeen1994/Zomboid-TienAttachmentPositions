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
  once per world): body scripts get factory + the player's delta (offset added, turn composed as below, scale
  multiplied); every other script (item models) gets an unchanged copy, because `addStatic(parent, model, name, name)`
  also looks up the item model's **own** attachment of that name (Plysken's masks and tents fine-tune themselves that
  way), so without it those items would lose their own offset on a copy.
- Turning (`Core.Turn`, 0.1.6): the game turns a point with `rotateXYZ(x, y, z)` = Rx · Ry · Rz, X first and each
  later axis in the already turned frame. 0.1.5 and earlier added the slider degrees to those angles, so on a point
  whose own Y is ±90 Turn X and Turn Z spun around the same line (gimbal lock; reported 2026-10-12). 193 of the 895
  body points in the server's mods are within 15° of that (Plysken's bag spots, HavenFall's flashlight spots,
  KATTAJ1's belts). Now the player's turn is its own Rx · Ry · Rz around the **bone's** axes (the same axes Move X / Y /
  Z use), multiplied in front of the point's own turn, and the product is decomposed back into X, Y, Z for
  `getRotate():set` (Y from `atan2` + `sqrt`, as vanilla never uses `math.asin`). No turn = the point's own angles
  exactly. Saved turns from 0.1.5 and earlier are read with the new meaning.
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

Copies are never removed: saved characters and corpses may name them. A registered point always carries the player's
items on their copy (`Core.Want` / `Target`), at factory values when they have none (reset), so nothing moves between
base and copy while editing (0.1.7 and earlier went back to the base at identity, a pair of attach packets each time
a drag crossed zero). Factory values are read the first time a point is copied; with
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
  The client also normalizes its local players every 2 s (`Client.CHECK_MS`, once its own id is known).
- The first `hello` waits until `getSpecificPlayer(0):getOnlineID() >= 0` (checked at `OnGameStart`, then every
  tick; single player sends at once). A client fires `OnGameStart` before `sendPlayerConnect`, so a command sent there
  reaches a server with no player on that connection and is dropped (`receiveClientCommand: player is null`). With
  0.1.4 on the dedicated server (2026-10-11) request 1, sent at `OnGameStart` (frame 0), never got an answer in two
  relogs; request 2, 3 s later, was answered within 1.5 s, so positions came back about 4.5 s after joining.
  `hello` is still repeated every second (`Client.HELLO_MS`, up to 20 times) until `all` arrives. The online ID wait
  did not help: in the 0.1.6 log (2026-10-12) the ID was already set at `OnGameStart`, request 1 (frame 0) was still
  lost and request 2 (3.5 s later at the old 3 s interval) was answered within two frames, so the retry is what
  works and it was shortened from 3 s to 1 s in 0.1.7.
- Log lines (all `[TienAttachmentPositions] ...`; the ones marked * start with `Core.VERSION`, which must match
  mod.info, so the log shows which copy each side runs): server `loaded the positions of N players`* (world init) and
  `sending positions to <user> (their spots: N, their version: V)`* (hello); client `asking the server for positions
  (request N)`*, `model scripts with points: N, bodies: 2, body
  points: M` (first index build per world), `positions from the server: N players, yours: K spots` (all), and the
  first 20 moves per session as `<user>: <location> -> <location>` (a pair repeating every 2 s = something keeps
  putting the item back on the base location), `the server never sent the positions (N requests)`.

### Protocol (module `TienAttachmentPositions`)

Client → server: `hello`, `set {ps, v, seq}` (a list of points that all take `v`; nil or identity = reset; a single
`p` is still accepted), `resetAll`. Server → client: `all {ids, reg, pts}`, `pt {u, n, ps, v, seq}` (to everyone, one
per `set`, so a slot of 15 points is one packet each way), `resend` (to one player). Single player calls the other side's handler
directly (`Core.ToServer` / `ToClient`; `sendServerCommand` does nothing there).

Server checks: the point must be a known attachment name of a base location (from the group), not `head_hat` /
`bowtie` (Java never sends those), no `@` or `:`, not a body location name (`Core.Adjustable`), at most 300 points a
player and 64 per `set` (`Core.MAX_SLOT_POINTS`); values clamped (move ±0.5, turn ±180, size 0.25-3, rounded to
0.001).

Store: global mod data `TienAttachmentPositions` = `{ ids = {user = ns}, next, reg = {ns = {point = true}},
pts = {ns = {point = {ox, oy, oz, rx, ry, rz, s}}} }` (string keys everywhere).

### Per slot (0.1.7)

Values are stored per point, but the window edits a **slot**: `Client.SlotPoints(item, point)` = the item's own point,
then every adjustable body point of the locations in its hotbar slot's definition (`item:getAttachedSlotType()` →
the `ISHotbarAttachDefinition` entry of that `type`, its `attachments` values, plus the `replacement` values of every
`ISHotbarAttachDefinition.replacements` entry with the same `name`: vanilla's Back slot swaps to the "... with Bag"
locations while a bag is worn). Each item type in a slot hangs from its own location and point (Back: a bat on "Big
Weapon On Back", a rifle on "Rifle On Back"), so per point a weapon attached later started at its factory spot
(reported 2026-10-12). Since turns are around the bone's axes (0.1.6), one move / turn / size means the same for every
item in the slot. The attach wrapper cannot know the slot itself: vanilla sets `setAttachedSlotType` **after**
`setAttachedItem` (`ISHotbar:attachItem` ~376, `ISAttachItemHotbar:complete` ~67), so grouping happens when editing
and the per-point storage, copies and protocol stay as they were. The definitions are client Lua
(`client/Hotbar/ISHotbarAttachDefinition.lua`, plus slot mods' client files), so the server only checks each point.
A point shared by two slots follows whichever slot was edited last. The window shows the item's own point's values.

A replacement value joins a slot only when its key is one of that slot's `attachments` keys: Alice's Weapon Sling
(3775549570) files its bag spots (`AliceSlingRifleBag`...) in vanilla's Back replacement under keys like
`RifleAliceSling` and uses them only for its Sling (Back) slot (`resolveReplacementSlot`), so matching by name alone
put them in vanilla's Back slot. They are not in the sling slot's group either: open the window while the sling item
hangs on the bag spot to include it (the item's own point is always in the group).

A 0.1.8 draft filled unset points of a slot from its other points every 500 ms and learned points seen in use; the
user chose a Save button instead (2026-10-12), so nothing is checked periodically besides the 2 s `Normalize`.
Settings saved per point before 0.1.7 line up once Save is pressed in the window.

### Editing: preview, Save, resets (0.1.8)

Sliders only preview: `Client.Preview` applies the window's values to the player's own copies on this screen
(`Core.ApplyValues(ns, point, v)`; nothing sent, nothing stored). A point not registered yet cannot be previewed (no
copy to move the item to, and the attach of a copy location must reach every client after its registration), so the
first preview calls `Client.Prepare`: one `set` of identity values for the slot's unregistered points only, which
registers them everywhere without changing their look; the `pt` echo makes the window re-apply its preview
(`Window:serverUpdate`, which keeps the sliders while there are unsaved changes). **Save** = `Client.Edit` of the
window's values for every point of the slot + `Flush`: one `set`, one `pt` to everyone. Closing with unsaved changes
re-applies the stored values (`Preview(nil)`). **Reset this slot** / **Reset every slot** ask with an `ISModalDialog`
(yes / no) and on yes save at once (identity `set` for the slot / `resetAll`), no Save needed. Each `set` has a
sequence number per user and point (one for all the points of a slot); an echo older than the latest local one is
registered but its values are ignored.

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
  which the hotbar's right-click menu fires too), Plysken switch-off, `hello` once the online ID is known.
- `client/TienAttachmentPositions_Window.lua`: the window. Everything is measured from the font
  (`getFontHeight`, `MeasureStringX`): label column = widest label, value column = "-180.000", sliders 12 font heights
  (shrunk to fit the screen width, at least 100), heading and note word-wrapped, buttons sized to their text and
  wrapped onto more rows when needed, the note dropped when the window would be taller than the screen.

## Tests

`scripts/test`: `mock.lua` imitates the Java side (location group with `checkValid`, model scripts, class
metatables, players, commands); `run.py` runs single player and a server with three clients, routing commands and
attach packets the way the game does (Java-side attaches call the original method, not the wrapper), plus a second
server with two clients driving the real window (preview, Save, close, both resets); `ui_mock.lua` holds the stand-ins
for the vanilla UI classes (a dialog answers through `M.dialog:answer("YES")`); `win.py` builds the window at several
font and screen sizes and checks for overflow and overlaps. Needs lupa:
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
