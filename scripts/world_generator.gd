class_name WorldGenerator
extends RefCounted
## Generates the block data for a cube world.
##
## The planet is a "Chebyshev sphere": a voxel belongs to the face of whichever axis
## dominates its offset from the centre, and its depth is max(|x|, |y|, |z|).
## Terrain height is sampled from 3D noise at the voxel's projection onto a cube,
## so heights stay continuous across face edges.

const SIZE := 64
const HALF := 32.0
const DIRS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

var biome: String
var world_seed: int

var base := 22.0          # average surface depth from the centre
var amp := 4.0            # terrain height variation (+/-)
var sea := 0.0            # fluid fills air below this depth (0 = no fluid)
var top_block := Blocks.MOSS
var filler_block := Blocks.SOIL
var deep_block := Blocks.SLATE
var shore_block := Blocks.SAND
var fluid_block := Blocks.WATER
var caves := false
var tree_attempts := 0
var tree_ground := Blocks.MOSS
var ore_chance := 0.012

var _height := FastNoiseLite.new()
var _cave_a := FastNoiseLite.new()
var _cave_b := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(p_biome: String, p_seed: int) -> void:
	biome = p_biome
	world_seed = p_seed
	_rng.seed = p_seed
	_height.seed = p_seed
	_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height.frequency = 0.045
	_height.fractal_type = FastNoiseLite.FRACTAL_FBM
	_height.fractal_octaves = 4
	for n in [_cave_a, _cave_b]:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX
		n.frequency = 0.06
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	_cave_a.seed = p_seed + 101
	_cave_b.seed = p_seed + 202

	match biome:
		"grass":
			caves = true
			tree_attempts = 150
		"desert":
			top_block = Blocks.SAND
			filler_block = Blocks.SANDSTONE
			shore_block = Blocks.SAND
			amp = 3.0
		"snow":
			top_block = Blocks.SNOW
			filler_block = Blocks.SOIL
			shore_block = Blocks.SNOW
			fluid_block = Blocks.ICE
			sea = 20.0
			amp = 5.0
			tree_attempts = 120
			tree_ground = Blocks.SNOW
		"lava":
			top_block = Blocks.BASALT
			filler_block = Blocks.BASALT
			deep_block = Blocks.SLATE
			shore_block = Blocks.BASALT
			fluid_block = Blocks.LAVA
			base = 21.0
			amp = 5.0
			sea = 20.0
		"ocean":
			base = 20.0
			amp = 5.0
			sea = 21.0
			tree_attempts = 120


func generate() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * SIZE)
	var max_s := base + amp + 1.0
	var min_s := base - amp - 1.0
	var top_limit := maxf(max_s, sea)

	for z in SIZE:
		for y in SIZE:
			for x in SIZE:
				var o := Vector3(x + 0.5 - HALF, y + 0.5 - HALF, z + 0.5 - HALF)
				var d: float = max(absf(o.x), absf(o.y), absf(o.z))
				if d > top_limit:
					continue
				var i := x + y * SIZE + z * SIZE * SIZE
				var id: int
				if d < min_s - 4.0:
					id = deep_block
					if deep_block == Blocks.SLATE and _rng.randf() < ore_chance:
						id = Blocks.CRYSTAL
				else:
					var level := _surface_level(o, d)
					if d >= level:
						if sea > 0.0 and d < sea:
							data[i] = fluid_block
						continue
					var layer := int(level - d - 0.5)  # 0 = top layer
					var near_sea := sea > 0.0 and level <= sea + 1.0
					if layer == 0:
						id = shore_block if near_sea else top_block
					elif layer < 4:
						id = shore_block if near_sea else filler_block
					else:
						id = deep_block
				if caves and d > 7.0 and id != top_block:
					if absf(_cave_a.get_noise_3d(x, y, z)) < 0.075 and absf(_cave_b.get_noise_3d(x, y, z)) < 0.075:
						continue
				data[i] = id

	for t in tree_attempts:
		_try_tree(data)
	return data


func _surface_level(o: Vector3, d: float) -> float:
	var q := o * (base / d)  # projection onto a cube of half-size `base`
	var n := _height.get_noise_3dv(q)
	return clampf(roundf(base + n * amp * 1.8), base - amp, base + amp)


static func idx(p: Vector3i) -> int:
	return p.x + p.y * SIZE + p.z * SIZE * SIZE


static func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < SIZE and p.y < SIZE and p.z < SIZE


func _try_tree(data: PackedByteArray) -> void:
	var f := _rng.randi_range(0, 5)
	var up: Vector3i = DIRS[f]
	var a := 0 if up.x != 0 else (1 if up.y != 0 else 2)
	var sgn := up[a]
	var t1 := (a + 1) % 3
	var t2 := (a + 2) % 3
	var lim := int(base) - 6
	var p := Vector3i()
	p[t1] = int(HALF) + _rng.randi_range(-lim, lim - 1)
	p[t2] = int(HALF) + _rng.randi_range(-lim, lim - 1)
	# Walk from the outside of the world inward until we hit the ground.
	for k in range(int(HALF) - 1, -1, -1):
		p[a] = int(HALF) + k if sgn > 0 else int(HALF) - 1 - k
		var id := data[idx(p)]
		if id == Blocks.AIR:
			continue
		if id == tree_ground:
			_plant_tree(data, p, up)
		return


func _plant_tree(data: PackedByteArray, ground: Vector3i, up: Vector3i) -> void:
	var h := _rng.randi_range(3, 5)
	# Need clear air above.
	for k in range(1, h + 3):
		var q := ground + up * k
		if not in_bounds(q) or data[idx(q)] != Blocks.AIR:
			return
	data[idx(ground)] = Blocks.SOIL
	var a := 0 if up.x != 0 else (1 if up.y != 0 else 2)
	var e1 := Vector3i()
	var e2 := Vector3i()
	e1[(a + 1) % 3] = 1
	e2[(a + 2) % 3] = 1
	for k in range(1, h + 1):
		data[idx(ground + up * k)] = Blocks.TRUNK
	# Round, slightly squashed canopy centred on the top of the trunk.
	var r := _rng.randf_range(2.0, 2.7)
	var ri := int(ceil(r))
	var centre := ground + up * h
	var leaf: int = Blocks.FOLIAGE_KINDS[_rng.randi_range(0, Blocks.FOLIAGE_KINDS.size() - 1)]
	for k in range(-ri, ri + 1):
		for i in range(-ri, ri + 1):
			for j in range(-ri, ri + 1):
				var dist := Vector3(i, k * 1.25, j).length()
				if dist > r + _rng.randf_range(-0.3, 0.3):
					continue
				var q := centre + up * k + e1 * i + e2 * j
				if in_bounds(q) and data[idx(q)] == Blocks.AIR:
					data[idx(q)] = leaf
