# Paper Boy: Morning Delivery

An open-world bicycle newspaper-delivery game built with **Godot 4.7 (GDScript)** and **Blender 5.2**.
Ride through the Maple Heights district on an early morning, pick up papers at the Daily Herald depot,
deliver them to the highlighted houses, and get back before the deadline.

## Running

- **Editor:** open Godot 4.7, *Import* → select `project.godot` in this folder, then press F5.
- **Command line:**
  ```sh
  /Applications/Godot.app/Contents/MacOS/Godot --path "/Users/shreeram/Desktop/paperboy 3d"
  ```
- **Automated test (headless):**
  ```sh
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_milestone1.gd
  ```
  Living-city test (traffic, pedestrians, dog and cat):
  ```sh
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://tests/test_milestone4.gd
  ```
  Both print PASS/FAIL per check and exit non-zero on failure.

## Controls

All bindings live in *Project Settings → Input Map* and can be rebound there.

| Key | Action |
| --- | --- |
| W / ↑ | Pedal |
| S / ↓ | Brake; hold while stopped to reverse |
| A D / ← → | Steer (also turns the bike around at a standstill) |
| Space | Hop / bunny-hop |
| C or V | Toggle first-person / third-person view |
| E | Deliver paper / interact (depot) |
| B | Bell (pedestrians ahead step aside) |
| R | Reset to last safe position |
| H | Show/hide the controls hint |
| Esc or P | Pause menu (resume, restart, quit, master volume) |
| Right mouse drag | Look around (third person) |
| M | Toggle the large town map (a GTA-style radar is always shown at the bottom left) |

## How to play

1. Start at the depot forecourt and press **E** to load papers. This starts the route timer.
2. Follow the arrow at the top left. Route houses have glowing beams, and the blue one is the nearest.
3. **Slow down** at a house's gate or front path and press **E** to deliver.
4. When every paper is delivered, ride back to the depot to see your results. You can also press E twice at the depot to end a route early.

Wrong addresses and crashes cost points. Late deliveries score half.

**Crashes:** hit a wall, car or obstacle hard enough and the paperboy is thrown off. Harder hits throw him further. He gets up, walks back, picks up the bike and climbs back on. Hold W, S or E to hurry him up.

**Watch out for:**
- **Traffic** on Main Road, Birch Lane, Oak Avenue, Maple Street and Elm Street. Cars brake for you, but cutting in front of one knocks you over. Cross at the zebra crossings.
- **Pedestrians** on the sidewalks.
- **The dog on Park Road:** when it growls, pedal away. It gives up after a few seconds.
- **Cats**, which bolt away from you, never into the road.
- **Puddles**, which splash and slow you down.
- **Roadworks** on Maple Street and Park Road.

**Shortcuts:** two gravel back alleys cut through the blocks between Birch Lane and Main Road. One has a crate slalom; the other has a ramp jump over a log.

Each finished route unlocks a longer one: one more house, with the deadline scaled to match.

## Building a macOS app

`export_presets.cfg` has a macOS preset (universal, ad-hoc signed). Install Godot's export templates once: in the editor, *Editor → Manage Export Templates → Download and Install* (about 1.3 GB). Then run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "macOS" build/PaperBoy.zip
```

## Regenerating assets

| What | Command |
| --- | --- |
| Bicycle | `Blender -b --factory-startup --python assets/blender/build_bicycle.py` |
| Props, car, animals, shrub, flower bed | `Blender -b --factory-startup --python assets/blender/build_props.py` |
| Rider / pedestrian | `Blender -b --factory-startup --python assets/blender/build_rider.py [-- pedestrian]` |
| House kit | `Blender -b --factory-startup --python assets/blender/build_houses.py` |
| Sound effects | `python3 assets/audio/source/gen_audio.py` (needs numpy) |
| Pixabay photo textures | `python3 assets/textures/source/pixabay_fetch.py search "<query>" sheet.png`, then `... get <id> <name>` (needs `PIXABAY_API_KEY` in `~/.zshrc`) |
| Openverse sound effects | `python3 assets/audio/source/openverse_fetch.py search "dog bark"`, then `... get <id> <name> [--loop] [--start s --dur s]` (needs ffmpeg) |
| Newspaper textures and models | `python3 assets/textures/source/gen_newspaper.py` (needs Pillow), then `Blender -b --factory-startup --python assets/blender/build_newspaper.py` |

## Developer command-line hooks

Pass these after `--`. They are used for automated screenshots:

```
--shot=/abs/out.png --shot-frames=200   # save a screenshot and quit
--fp                                    # start in first person
--at=x,z,yaw_deg                        # start position
--start-route                           # load papers immediately
--cam=x,y,z,tx,ty,tz                    # free camera looking at a point
--deliver-next                          # deliver to the nearest route house
--map                                   # open the large map
--results                               # show a sample results screen
```

## Layout

See `docs/GAME_DESIGN.md` for the design, `PROGRESS.md` for status, `docs/ASSET_MANIFEST.md` for assets,
and `docs/TEST_PLAN.md` for tests.
