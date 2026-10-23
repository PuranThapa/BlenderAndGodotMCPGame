# Game Design — Paper Boy: Morning Delivery

## Pillars
1. **Readable, comfortable riding.** Arcade-sim feel: predictable acceleration, braking, lean and jumps. No harsh camera effects.
2. **Delivery as the core loop.** Depot → route → deliver → return → results.
3. **A believable morning town.** A coherent, lived-in district in fixed early-morning light. Night is never part of normal play.
4. **Fair challenges.** Hazards are readable and avoidable. There are alternate routes, and penalties are forgiving.

## World: Maple Heights (district 1)
The district is a 220 m × 220 m area on a 3 × 3 road grid. A low stone wall and a tree line mark the edge of town.

| Road | Axis | Width | Character |
| --- | --- | --- | --- |
| Birch Lane | E–W, z = −60 | 7 m | Residential, houses on both sides |
| Main Road | E–W, z = 0 | 10 m | Shops, depot, zebra crossings, future traffic |
| Park Road | E–W, z = 60 | 7 m | Residential |
| Oak Ave / Maple St / Elm St | N–S, x = −60 / 0 / 60 | 7 m | Connectors with hedges and trees |

- **Depot** (Daily Herald distribution) is on the north side of Main Road at x ≈ −30. The player spawns there.
- **Park** fills the block at x 0–60, z 0–60. It has paths, a pond, benches and a BMX corner with two ramps and a log jump.
- Blocks are raised 10 cm slabs, so every road edge has a curb that can be ridden over.
- The city is generated from code (`scripts/city/city_builder.gd`) with a fixed seed. The layout is identical on every run.

## Player bicycle
- `CharacterBody3D` with a lying capsule about 1.75 m long. The speed is a scalar along the heading.
- Steering uses a kinematic bicycle model (wheelbase 1.05 m). The available steering lock narrows as speed rises. A low-speed assist lets the player turn on the spot.
- Brake slows the bike to a stop. After a 0.6 s hold at a standstill, holding brake reverses at up to 2 m/s.
- Space does a small hop. Ramps launch the bike using the climb rate it had on the slope.
- Hitting a wall above step height (0.2 m) faster than 7 m/s triggers a crash: the bike tips over, recovers after 1.6 s, and the player loses 10 points.
- Curbs and slopes never cost speed. R returns the player to the last safe position, which is saved every 1.5 s while grounded.
- The visual lean follows lateral acceleration. Wheel spin, steering, cranks, and IK legs and arms are driven by the controller.

## Cameras
- **Third person:** a top-level rig follows with exponential smoothing and yaw lag. A SpringArm3D prevents wall clipping. Right-mouse drag orbits, then eases back.
- **First person:** a yaw-only mount, so the horizon stays level when the bike leans. Pitched 20° down so the stem, basket, levers and hands are visible. The head mesh is hidden.
- Toggling only switches `Camera3D.current`. Movement state is never touched.

## Delivery loop
| Event | Score |
| --- | --- |
| On-time delivery | +100 |
| Late delivery (after the 7:00 deadline) | +50 |
| Wrong address (house not on the route) | −10, no paper used |
| Crash | −10 |
| Clean jump (more than 0.6 s in the air) | +5 |
| Finish with all deliveries before the deadline | +0.5 per second remaining |
| Perfect route (none missed, none wrong) | +100 |

- Routes have 5 houses: about half across Main Road and half near the depot. The seed changes with each route.
- The player gets 2 spare papers on top of the route count.
- You must slow to under 3.5 m/s (12.6 km/h) to deliver. A paper arcs from the rider to the doorstep.
- Delivering twice to the same house is blocked. A route can be ended early at the depot; missed houses are reported.
- Earnings are score × $0.05.

## AI (implemented in Milestone 4)
- **Vehicles:** 2 closed lane loops with rounded corners. Cars run a forward scan every 0.1 s (staggered) for the player, pedestrians, animals and cars, keeping a 4.5 m gap and slowing to 5 m/s for corners. Junctions are reserved for one car at a time, and stuck recovery lets a car creep past after 10 s. Pedestrians on a zebra are in the lane, so cars stop for them automatically.
- **Pedestrians:** sidewalk loops 1.25 m in from the kerb, plus zebra walkers who wait for a gap (no car within 28 m approaching). They stop for the player in their path and flinch when a bike passes within 2.2 m at more than 5 m/s.
- **Dogs:** yard-bound dogs bark. One "chaser" telegraphs (barks, then crouches) before a short chase with a leash radius.
- **Cats:** idle, sit and stroll. They flee from the bike and never path into a moving bike's lane.
- **All agents:** simple state machines, staggered updates, and stuck detection that resets the agent to its last waypoint.

## Challenges and progression
- **Back alleys:** gravel shortcuts through the blocks between Birch Lane and Main Road. Block 5 has puddles, a crate slalom and bins; block 9 has a kicker ramp and a log jump.
- **Roadworks:** half of Maple Street (south of Main Road) and half of Park Road are closed with solid barriers.
- **Puddles:** splash, −15% speed, 1 s cooldown.
- **Traffic, dogs and pedestrians** are described in the AI section.
- **Progression:** route n has 5 + min(n − 1, 3) houses, a deadline of 60 + 72 s per house, and spare papers of max(1, 2 − floor((n − 1) / 2)).

## Audio
All sounds are synthesized (see `docs/ASSET_MANIFEST.md`).
- Bike loops follow speed, pedalling and whether the bike is grounded.
- Traffic engines are positional, with pitch following speed.
- Barks, meows, horns and splashes are positional one-shots.
- Ambience beds are birds, city hum and wind.

## Out of scope for now
Night, weather, throw-aim mini-game, multiple districts, saving progression.
