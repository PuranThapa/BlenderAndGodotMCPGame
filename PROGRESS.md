# Progress

## Environment (verified 2026-10-23)
- macOS on an Apple M1 Pro. Godot **4.7.2.stable** (Forward+ on Metal) at `/Applications/Godot.app`. Blender **5.2.2 LTS** at `/Applications/Blender.app`.
- **Godot MCP:** `run_project`, `get_debug_output` and `stop_project` are used for debug-mode launches, which show GDScript warnings. Scenes and scripts are written as files.
- **Blender MCP:** `execute_blender_code` hung during a long build and render, so all asset builds run in **headless Blender from the CLI** (reproducible, about 4 s each, and the open Blender UI is untouched). The interrupted MCP call may have left a stray "Bicycle" scene in the open Blender file; it is safe to delete.

## Milestones
| # | Milestone | Status |
| --- | --- | --- |
| 1 | Playable graybox: riding, cameras, delivery | ✅ |
| 2 | Blender → Godot pipeline: bicycle, rider, pedestrian, house kit, props, car, animals | ✅ |
| 3 | Delivery system: route, inventory, markers, score, results, progression | ✅ |
| 4 | Traffic and living city: cars, pedestrians, dogs, cats | ✅ |
| 5 | Ramps, polish, audio, minimap, challenges | ✅ |
| 6 | Regression and packaging | ✅ except the final `.app` build, which is waiting on Godot export templates (see below) |

### Milestone 5: polish (2026-10-23)
- **Audio:** 21 synthesized sound effects (`assets/audio/source/gen_audio.py`), all original work, CC0. Inspected as spectrograms because they couldn't be listened to here.
  - **Bike:** rolling, freewheel ticks and chain loops follow speed and pedalling; brake squeal and bell.
  - **Town:** car engines (pitch follows speed), horns when the player blocks a car, dog barks and a growl, cat meows, puddle splashes.
  - **Delivery and UI:** paper whoosh and landing, chimes, buzz, fanfare, UI clicks.
  - **Ambience:** birds, city hum and wind.
  - Master volume is in the pause menu.
  - Audio stays silent in headless runs so tests exit clean.
- **Bell (B):** pedestrians ahead step aside.
- **Minimap:** drawn from the city data at the top right; M opens a large map with street names. Shows route houses (cyan for the nearest), the depot, traffic, dogs and the player arrow.
- **Route challenges:**
  - Two back-alley shortcuts with brick walls, gravel, puddles, a crate slalom, bins, and a kicker ramp over a log.
  - Roadworks closing half of Maple Street and half of Park Road (cones, striped barriers, spoil heap, sign).
  - Puddles that splash and cost about 15% speed.
  - A bus stop on Main Road.
- **Environment detail:**
  - Kerb drains, manhole covers and asphalt patches.
  - Shrubs and flower beds (Blender) in every front garden.
  - Sash windows on the upper floors of shops.
- **Progression:** each route adds a house (5 → 8), the deadline scales at 72 s per house plus 60 s, and spare papers drop. The results screen announces the next route.
- **Launch:** a 1.25 s title-card fade-in hides the first-second shader-compilation hitch.

### Milestone 6: regression and packaging (2026-10-23)
- **Headless tests:**
  - `test_milestone1.gd`: **61/61** (riding, cameras, curbs, crash, ramps, puddle, alley jump, roadworks, delivery loop, footpath drops, pause, results, progression).
  - `test_milestone4.gd`: **23/23** (traffic overlap-free over 180 s, yielding, pedestrians, dog, cat, a full route with the town alive).
  - The living-city test has a wall-clock watchdog so it can't hang.
- **Fresh windowed launch:** no output errors.
- **Godot MCP debug run:** **0 errors, 0 warnings**, after fixing 6 GDScript warnings.
- **No leaks at exit:** looping audio playbacks were found leaking in headless runs and fixed.
- **Packaging:** `export_presets.cfg` (macOS, universal, ad-hoc signed, excludes tests and sources) and ETC2/ASTC texture import are set up. The export reaches the "no export template" stage. **Godot's official export templates (1.28 GB) are not installed.** Once they are (Editor → Manage Export Templates → Download and Install), run:
  `Godot --headless --path . --export-release "macOS" build/PaperBoy.zip`

### Definition of done (first playable demo)
- [x] The Godot project opens and runs
- [x] Ride a bicycle through a small connected district
- [x] First-person and third-person camera modes both work
- [x] Finite number of newspapers
- [x] At least 5 delivery targets in one route
- [x] Deliveries tracked and a route result displayed
- [x] At least one moving vehicle *(6 cars on 2 loops)*
- [x] At least one pedestrian, one dog and one cat *(6 pedestrians, 2 dogs, 2 cats, all with behaviour)*
- [x] At least one ramp can be jumped *(3: two in the park, one in an alley)*
- [x] Collision and recovery are usable *(automated checks only; a human keyboard playtest is still recommended)*
- [x] Morning lighting and a coherent realistic direction *(stylised-realistic: Blender assets plus procedural facade and roof shaders)*
- [x] Key environment and bicycle assets made through Blender → Godot
- [x] Runs without blocking errors *(0 errors and 0 warnings in a debug run)*
- [x] README, PROGRESS, ASSET_MANIFEST and TEST_PLAN updated

### Polish pass 2 (2026-10-23, user requests)
- **Foot down when stopped:** at a standstill the rider slides forward off the saddle and plants the left foot on the ground beside the bike. The bike leans about 7° onto it, and the right pedal rotates up and forward, ready to push off. Everything blends back when you ride away.
- **A real newspaper:** a printed Daily Herald front page and inside spread (`assets/textures/source/gen_newspaper.py`). There is a Blender folded copy with a slight bow, page edges, a fold and a red rubber band, and an open broadsheet.
  - Papers leave the rider's right hand, spin like a frisbee and land flat on the footpath spot.
  - A throwing-arm animation plays on each delivery.
- **Depot clerk:** a seated townsperson in a cardigan at a chair and side table with a mug and a paper stack.
  - Reads the open Herald (front page facing out) and turns pages now and then.
  - When you arrive: lowers the paper, looks at you, waves and greets you.
  - Comments when a route starts and ends.
- **GTA-style radar:** round, bottom-left, rotates with your heading.
  - North marker on the rim; edge blips for the next house and the depot when off-radar.
  - Shows traffic, dogs and pedestrians. The speed panel sits beside it. M still opens the full north-up map.
- **Head look:** the rider glances at the next house when it's within 16 m.
- **Tests:** `test_milestone1.gd` is now **69/69** (adds foot-down, ride-off, clerk reading and greeting, papers landing flat); `test_milestone4.gd` **23/23**; debug run **0 errors / 0 warnings**.

### Pixabay photo textures (2026-10-23)
- The Pixabay API key is stored in `~/.zshrc` (`PIXABAY_API_KEY`) and is never written to the project.
- New tool `assets/textures/source/pixabay_fetch.py`: search with contact sheets, then download, flatten lighting, make seamless, generate normal maps, and log credits.
- **Applied:** asphalt (roads), grass (lawns, park, countryside), concrete (sidewalks and paths), hedge leaves (all hedges), gravel (alleys). All are world-space triplanar with normal maps; imported with mipmaps and VRAM compression.
- **Verified:** 2×2 tiling sheet (no visible seams except mild repetition on the gravel); in-game street, ground, alley and aerial screenshots. Tests still pass (69/69 and 23/23), the debug run is clean, and frame rate holds at 120 FPS.
- **Next candidates:** brick and roof-tile photos to replace the procedural facade and roof shaders. They have regular patterns, so they need careful tile-aligned crops rather than the blend-to-seamless method.

### Real sound recordings from Openverse (2026-10-23)
- **Pixabay audio was checked first:** its audio API returns **403** for this key (approved accounts only), and its sound-effects website returns **403** to scripts. Images and videos via the API work.
- **New tool:** `assets/audio/source/openverse_fetch.py` uses the Openverse API with no key. It filters to commercial-and-modification-safe licenses, converts with ffmpeg, trims, levels and loops, writes waveform/spectrogram check images, and logs credits.
- **15 real recordings now in use:**
  - dog barks (2 variants), dog growl (now the chaser's warning), cat meows (2 variants)
  - bicycle bell, car engine idle loop, car horn
  - puddle splash, newspaper landing, bike crash
  - freewheel ticking loop, chain loop
  - morning birds loop, city street loop
- **Selection:** each recording was chosen from candidates by inspecting waveforms and spectrograms. Rejected: a bell with a single "ding". Re-cut: birds (loud dove coos removed), horn (long blast removed), splash and paper (lead-in trimmed), chain (fade-out removed).
- **Levels:** each recording is loudness-matched to the synthesized sound it replaced.
- **Verified:** a windowed run with the real audio driver loads every recording (`-- --audio-report`); the debug run is clean; tests pass (69/69 and 23/23). **The sounds have still not been listened to.** Please report anything that sounds wrong or too loud.

### Realistic trees (2026-10-23)
- **Before:** the trees were lumpy blob spheres on a plain trunk.
- **Now:** three species (oak, maple, birch) built procedurally in Blender (`build_trees.py`):
  - A branching trunk, limbs and twigs with photo bark (Pixabay oak and birch bark, with normal maps).
  - About 300 leaf-cluster cards per tree, made from real leaf photos (`make_leaf_atlas.py`, using a transparent Pixabay leaf cut-out).
- **New leaf shader** (`assets/materials/leaves.gdshader`): alpha cut-out, two-sided, sunlight through the leaves, distance-stable alpha, and gentle wind sway.
- **Fixed after screenshot review:**
  - Drawn twig lines in the atlas showed as dark fans, so they were removed (the 3D branches supply the wood).
  - Wide crowns clipped into houses, so yard trees are now slim birches or small maples set nearer the fence.
- **Verified:** Blender preview; in-game street, park, house close-up and aerial views. Tests 69/69 and 23/23; debug run clean; **120 FPS** in the aerial view with every tree visible (about 1.3M triangles).

### GTA-style crash sequence (2026-10-23)
- **New file:** `scripts/player/crash_sequence.gd`, driven by `bike_visual.gd`, with physics in `bicycle_controller.gd`. Poses are procedural keyframes with IK on the rider.glb segments.
- **Fall:** the rider is thrown along the impact direction.
  - Throw distance is 0.9–4.1 m and arc height 0.3–0.85 m, both scaling with impact speed (7–12 m/s). He tumbles through a tuck and a dive, lands face-down and slides to rest.
  - Walls and cars in the path shorten the throw; a head-on hit bounces him off sideways (about 115°). The landing spot is clamped to real ground, never a counter or wall top.
- **Bike:** tips over with gravity-like acceleration and a small bounce, slides and spins (more for harder hits), the front wheel flops and the wheels keep spinning down.
- **Recovery:**
  - Lies dazed for 0.5–1.8 s, then lifts his head.
  - Gets up: push-up, then one knee, then standing.
  - Turns and walks back to the bike with a proper gait.
  - Crouches, grabs the handlebar and saddle, and hauls the bike upright.
  - Steps round, swings his right leg over the rear wheel, and sits with the left foot down and the right pedal raised.
  - A 0.3 s cross-fade into the normal riding pose.
- **Hurry:** holding W, S or E speeds up the lying, get-up and walk phases (×1.8).
- **Camera:** pulls back and frames the midpoint between rider and bike. First person switches to third person for the crash and back afterwards.
- **Traffic safety:** the fallen rider is an "obstacle" that cars stop for. Before the fix, the first film showed a car driving over him.
- **Verified:** frame sequences filmed for hard, light and head-on wall crashes and reviewed.
  - Fixed after review: the rider landed on top of the depot counter in a wall crash.
  - New tests: the bike falls onto its side; all 7 phases run; the rider never enters the wall; the rider remounts (about 8.6 s for a 9 m/s wall hit); he ends in the stopped pose; a harder hit throws him further (3.8 m vs 1.7 m); traffic stops short of a fallen rider.
  - Tests **74/74** and **24/24**; debug run 0 errors, 0 warnings.
- **Dev hooks:** `-- --crash=<m/s> [--crash-wall] --film=<prefix> --film-every=N --film-count=N`.

## Known issues and limitations
- **No human playtest yet.** Steering feel, speeds, dog difficulty and the deadline need tuning by someone holding a keyboard. The pause menu and results buttons were exercised only through code paths and screenshots.
- **Audio has not been listened to.** Levels were set by RMS and judgement. Expect to rebalance volumes.
- **Art:** still stylised-realistic, not photoreal. Shop shells, the depot shell, roads and hedges are primitives with shaders. Characters and animals are rigid segments, not skinned meshes. Foliage is blob-based.
- **Traffic:** two fixed loops and no traffic lights. A junction is held by one car at a time; deadlocks are resolved by stuck recovery.
- **Packaging:** the `.app` build needs the export templates (see above).

## Suggested next steps
1. Install the export templates and build `build/PaperBoy.zip`.
2. Playtest and tune: `max_speed`, `pedal_accel` and steering lock in `bicycle_controller.gd`; the dog's `chase_speed` and `notice_range`; the deadline.
3. Art upgrades: skinned rider and animal rigs, leaf-card foliage, textured shopfronts, more house shapes (L-shaped plans, porches).
4. Content: a second district, traffic lights at Main Road, a bus on loop A, and a weather variant (keeping the morning).
