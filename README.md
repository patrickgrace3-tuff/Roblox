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

A platform-gun obby: climb a tall shaft by shooting your own footholds onto its walls.

- **Left click** — shoots a platform onto whatever surface is under your cursor (wall, floor, ceiling — any direction), up to 300 studs away.
- Each player can have at most **8 active platforms** at once; shooting a 9th removes their oldest one, so you can't just build a permanent staircase — you have to keep climbing.
- An orange **jump spring** sits at the base of the shaft, right before the walls — step on it for a 5x jump height boost that lasts for your next 10 jumps (re-touching it refreshes the boost).
- Reach the glowing green **Goal** platform at the top of the shaft to win.

## Optional: CI publishing via Open Cloud

For automated builds/publishing without Studio:
1. On Creator Hub, go to **Creator Dashboard > Open Cloud > API Keys** and create a key with `universe-places:write` permission scoped to your experience.
2. Use `rojo build` to produce an `.rbxlx`/`.rbxl` file, then upload it with the [Places Publish Open Cloud endpoint](https://create.roblox.com/docs/cloud/reference/Place) using that API key.
3. Store the API key as a repo secret (never commit it) if wiring this into GitHub Actions.
