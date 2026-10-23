# Test Plan

## Automated (headless)
`tests/test_milestone1.gd` loads `main.tscn` and drives the real input actions. Run it with:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_milestone1.gd
```

| Area | Checks |
| --- | --- |
| Input map | All 10 core actions exist and have key events |
| World | ≥ 5 deliverable houses; player rests on the ground at spawn |
| Riding | Pedal accelerates; bike moves forward; steering turns; brake stops; holding brake reverses |
| Cameras | Toggle to first person and back; speed unchanged across the toggle |
| Low speed | Can turn around from a standstill |
| Curb | Rides from road onto sidewalk without losing speed |
| Crash | A wall at speed triggers a crash with no clipping; the bike falls onto its side (roll > 1 rad); all 7 crash phases run; the thrown rider never enters the wall; the rider remounts and ends in the stopped pose; a harder impact throws the rider more than 1 m further |
| Ramp | Bike climbs the kicker, goes airborne, lands and stays grounded |
| Delivery | Depot start; papers = route + spares; can't deliver while fast; wrong address counted; all 5 houses detected and delivered; no duplicate delivery; inventory decrements; return to depot finishes the route; results correct |
| Challenges | A puddle splashes and scrubs speed; the alley kicker launches the bike and it clears the log; the Maple Street roadworks barrier blocks the road |
| Stopped pose | Rider settles into foot-down; left foot is less than 0.15 m off the ground; bike leans more than 0.08 rad; the foot returns to the pedal when riding off |
| Clerk | Seated at the depot; reading when alone; looks up, waves and greets when the player arrives |
| Paper landing | Every delivered newspaper lies flat within 0.2 m of its footpath spot |
| Pause | Route timer frozen while the tree is paused |
| Progression | Route 2 starts from the depot with 6 houses and a deadline of 60 + 72 × 6 s |

This test runs with the living city disabled (`LivingCity.enabled = false`), so it is deterministic. It also checks that every route house's paper lands on the footpath in front of the gate.

**Last result (2026-10-23): 74 passed, 0 failed.**

### Living city: `tests/test_milestone4.gd`
```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://tests/test_milestone4.gd
```
`--fixed-fps` runs the simulation faster than real time (3 simulated minutes take about 3 s). A wall-clock watchdog (90 s) fails the run instead of hanging.

| Area | Checks |
| --- | --- |
| Population | ≥ 5 cars, ≥ 4 pedestrians, dogs and cats present; no car spawns within 30 m of the player |
| Traffic | All cars move; **zero footprint overlaps** in 180 s (separating-axis test on 1.8 × 4.1 m boxes); cars stay on the road |
| Yielding | A car stops more than 2.5 m short of a stationary player, reports it is blocked by the player, doesn't hit them, and drives on after the player leaves |
| Pedestrians | All walk; a zebra walker crosses Main Road; a walker waits for the player blocking the path |
| Dog | Idles at home → telegraphs → chases → gives up and returns home |
| Cat | Flees an approaching bike, ends up more than 6 m away, and **never steps onto a road** |
| Fallen rider | An approaching car stops more than 2 m short of a rider lying in its lane |
| Integration | A full 5-house route can be completed with the whole town active |

**Last result (2026-10-23): 24 passed, 0 failed.**

## Visual / runtime checks (manual or screenshot hook)
Each one is captured with `-- --shot=... [--fp] [--at=x,z,yaw]` and then inspected:

- [x] Third-person spawn view: rider, bike, shadows, shops, HUD readable
- [x] First-person view: stem, basket, brake levers and hands visible; head hidden; horizon level
- [x] Aerial overview: connected district, boundary wall, park, depot
- [ ] Riding feel at speed with a keyboard (needs a human playtest)
- [ ] Pause menu buttons and volume slider (needs a mouse playtest)
- [x] Delivery screenshot: the paper lies on the footpath in front of the gate
- [x] Blender previews of every exported GLB (`assets/reference/*.png`), plus a re-import check with `preview_glb.py`
- [x] In-game: rider on the bike, house kit with shaders, parked cars, a walking pedestrian, and moving traffic
- [x] Minimap and large map (`--map`), results screen (`--results`), launch fade-in
- [x] Back alleys, roadworks, bus stop, gardens
- [x] Sound spectrograms (bell, bark, meow, horn, engine, birds, freewheel, splash, chime, crash, brake, whoosh)
- [ ] Listening test for audio levels and quality (not possible in this environment)

## Performance baseline (MacBook Pro M1 Pro, 1600×900 window, after shader warm-up)
| View | FPS | Draw calls | Objects | Primitives |
| --- | --- | --- | --- | --- |
| Residential street, first person | 119 (vsync-capped) | ~495 | ~1.7k | ~130k |
| Residential street, third person | 120 (vsync-capped) | ~523 | ~1.8k | ~129k |
| Main Road with traffic, NPCs and the full asset set (latest) | 118–120 | 600–2,300 | 1.5k–6.6k | 0.4M–1.4M |

The first 1–2 seconds after launch drop to about 40 FPS while shaders compile. A shader warm-up or pipeline cache is a Milestone 6 item.

## Regression checklist (run before every milestone sign-off)
1. Both headless tests pass.
2. A Godot MCP `run_project` debug launch shows **0 errors and 0 warnings** in `get_debug_output`. *(Last run 2026-10-23: clean.)*
3. A fresh windowed `--path` launch prints no errors, and nothing leaks at exit.
4. Screenshots of the spawn, first-person, aerial and challenge areas look correct.
