# Cube Worlds

A voxel sandbox game in Godot 4.7 where each world is a **64×64×64 cube planet**.
You can walk on all six faces: gravity always points toward the face you're over, and the
player smoothly rotates when walking over an edge. Other cube worlds (desert, snow, lava,
ocean, moss) float and slowly spin in the sky.

**Art style:** no textures. Blocks are flat pastel colours with soft bevelled edges,
smooth per-vertex ambient occlusion and slight per-block colour jitter. The ground is teal moss
over terracotta soil, trees have round canopies in coral, peach, mint, lilac or butter, and
the sky is a dusk gradient.

## Running
Open the folder in Godot 4.7+ and press **F5** (main scene: `scenes/main.tscn`).

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump (fly up in fly mode) |
| Shift | Sprint |
| Ctrl / C | Fly down |
| Mouse | Look |
| Left click | Break block |
| Right click | Place block |
| 1–9 / wheel | Select block |
| F | Toggle fly mode |
| R | Respawn |
| Esc | Release the mouse |

## Code layout
- `scripts/main.gd`: environment (sky shader that follows the player's "up"), lights, HUD, spawns the home world, the sky worlds and the player.
- `scripts/voxel_world.gd` (`VoxelWorld`): block storage, 16³ chunk meshing, collision, threaded generation, voxel raycast, gravity direction.
- `scripts/world_generator.gd` (`WorldGenerator`): terrain per biome. Depth is the Chebyshev distance `max(|x|,|y|,|z|)` from the centre, and height noise is sampled on the cube's projection, so terrain stays continuous across edges. Also adds caves, glowing crystals, and round-canopy trees that grow "outward" on every face.
- `scripts/player.gd` (`Player`): first-person controller with a custom up vector, plus block breaking and placing.
- `scripts/blocks.gd` (`Blocks`): block ids, the colour palette and the bevel/glow block shader.

## Debug
`godot --path . -- --screenshot=C:/tmp/shot.png` generates the worlds, saves a few screenshots
(including an automated walk over a cube edge) and quits.
