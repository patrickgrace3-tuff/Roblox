# Roblox

A code-first Roblox project synced with Roblox Studio via [Rojo](https://rojo.space).

## Project layout

```
src/
  server/   -> ServerScriptService
  client/   -> StarterPlayer.StarterPlayerScripts
  shared/   -> ReplicatedStorage
default.project.json  -> Rojo project definition
rokit.toml             -> pinned toolchain versions
```

## 1. Create the experience on Creator Hub

1. Go to [create.roblox.com](https://create.roblox.com) and sign in.
2. Click **Create experience**, give it a name, and confirm.
3. Note the experience's **Place ID** / **Universe ID** shown in the experience's dashboard (Basic Info page) — you'll need these later for publishing/CI.

## 2. Install tooling locally

1. Install [Roblox Studio](https://create.roblox.com/dashboard) if you haven't already.
2. Install [Rokit](https://github.com/rojo-rbx/rokit) (toolchain manager), then from the repo root run:
   ```
   rokit install
   ```
   This installs the pinned Rojo version from `rokit.toml`.
3. Install the Rojo Studio plugin:
   ```
   rojo plugin install
   ```

## 3. Sync this repo into Studio

1. Open the experience's place in Studio (from Creator Hub, click **Edit** on the experience, or use File > Open from Roblox Studio).
2. In the repo root, start the Rojo server:
   ```
   rojo serve
   ```
3. In Studio, open the Rojo plugin panel and click **Connect**. Your `src/` files will sync live into the place.

## 4. Publish back to Creator Hub

Once you're happy with changes in Studio, publish normally via **File > Publish to Roblox...** (or Ctrl+Alt+P) — this pushes the synced place to the experience you created in step 1.

## Gameplay

A platform-gun obby with a jungle theme: climb 200 studs up a grove of trees by shooting your own footholds onto their trunks.

- **Left click** — shoots a platform onto whatever surface is under your cursor (tree trunk, cliff, floor — any direction), up to 300 studs away.
- Each player can have at most **8 active platforms** at once; shooting a 9th removes their oldest one, so you can't just build a permanent staircase — you have to keep climbing.
- An orange **jump spring** sits at the base of the trees, right before the grove. Stepping on it grants 10 charge-jumps (shown as a "Jump Boost: N" counter) and refreshes if you touch it again. While active, normal auto-jump is replaced by a charge jump: **hold Space** to fill the on-screen meter (up to 1.2s) and **release** to jump — a quick tap jumps at normal height, holding the full meter jumps 5x as high.
- Reach the glowing green **Goal** platform at the top of the grove to win.
- The jungle level is procedurally generated: rows of climbable wood-trunk trees with leafy canopies on either side, a rock cliff backdrop, scattered rocks/bushes around the spawn floor, and a hazy green-tinted atmosphere/lighting for mood.
- Right next to it (offset along X, no overlap) is a second **beach** zone with the same climbing mechanic: sandy ground, an ocean backdrop, palm trees, and climbable sandstone rock pillars with translucent blue waterfall overlays draping down a back cliff. It has its own jump spring and goal. Note: with two `SpawnLocation`s now in the world, Roblox may spawn players in either zone somewhat unpredictably on join.
- A purple **magic carpet** pad sits on the jungle floor near spawn. Touching it permanently unlocks flight for that player (persists until they leave). Press **F** to toggle flying on/off — a carpet appears under your feet, **Space**/**Shift** move up/down, WASD steers, and movement speed increases while flying. There's no ground connecting the jungle and beach zones, so the carpet is also the way to fly across the gap between them.
- A third **dungeon** zone (further along X, its own `DungeonSpawn`) is a 400-stud-long torch-lit stone corridor ending in a 70x50 boss room. Every player spawns with a **sword and shield already equipped** (also still obtainable from the weapon rack near the entrance, now just decorative). A WoW-style **action bar** (bottom-center of the screen, 3 numbered slots) shows the combat abilities and glows while active: **1** toggles auto-swing (sword keeps swinging at nearby/facing enemies every 0.6s until pressed again), **2** activates a 3-second 100% damage-immunity shield, **3** fires a **bow and arrow** for a ranged hit-scan attack (up to 200 studs, with a glowing arrow visibly flying from the player to the impact point). A health bar shows bottom-left. Every mob has its own floating health bar above its head (with a name label for the boss) that shrinks as you damage it. ~11 chasing mobs are spread down the corridor, and it ends with **Nonna Fury**, an oversized angry chef wielding a giant spoon — defeating her spawns a golden victory pedestal.

## Optional: CI publishing via Open Cloud

For automated builds/publishing without Studio:
1. On Creator Hub, go to **Creator Dashboard > Open Cloud > API Keys** and create a key with `universe-places:write` permission scoped to your experience.
2. Use `rojo build` to produce an `.rbxlx`/`.rbxl` file, then upload it with the [Places Publish Open Cloud endpoint](https://create.roblox.com/docs/cloud/reference/Place) using that API key.
3. Store the API key as a repo secret (never commit it) if wiring this into GitHub Actions.
