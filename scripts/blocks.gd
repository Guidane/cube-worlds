class_name Blocks
extends RefCounted
## Block ids, their textures, and the shared procedurally generated texture atlas.

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const SAND := 4
const LOG := 5
const LEAVES := 6
const SNOW := 7
const WATER := 8
const LAVA := 9
const COAL_ORE := 10
const PLANKS := 11
const ICE := 12
const BASALT := 13
const SANDSTONE := 14
const COBBLESTONE := 15
const COUNT := 16

const NAMES := [
	"Air", "Grass", "Dirt", "Stone", "Sand", "Log", "Leaves", "Snow", "Water",
	"Lava", "Coal Ore", "Planks", "Ice", "Basalt", "Sandstone", "Cobblestone",
]

# Atlas tiles
const T_GRASS_TOP := 0
const T_GRASS_SIDE := 1
const T_DIRT := 2
const T_STONE := 3
const T_SAND := 4
const T_LOG_SIDE := 5
const T_LOG_TOP := 6
const T_LEAVES := 7
const T_SNOW := 8
const T_SNOW_SIDE := 9
const T_WATER := 10
const T_LAVA := 11
const T_COAL_ORE := 12
const T_PLANKS := 13
const T_ICE := 14
const T_BASALT := 15
const T_SANDSTONE := 16
const T_SANDSTONE_TOP := 17
const T_COBBLESTONE := 18
const TILE_COUNT := 19

const TILE := 16
const ATLAS_COLS := 8
const ATLAS_ROWS := 3

## For each block id: [top tile, side tile, bottom tile]. "Top" is the face pointing
## away from the planet's centre (the block's local up).
const FACE_TILES := [
	[0, 0, 0],                                    # AIR (unused)
	[T_GRASS_TOP, T_GRASS_SIDE, T_DIRT],          # GRASS
	[T_DIRT, T_DIRT, T_DIRT],                     # DIRT
	[T_STONE, T_STONE, T_STONE],                  # STONE
	[T_SAND, T_SAND, T_SAND],                     # SAND
	[T_LOG_TOP, T_LOG_SIDE, T_LOG_TOP],           # LOG
	[T_LEAVES, T_LEAVES, T_LEAVES],               # LEAVES
	[T_SNOW, T_SNOW_SIDE, T_DIRT],                # SNOW
	[T_WATER, T_WATER, T_WATER],                  # WATER
	[T_LAVA, T_LAVA, T_LAVA],                     # LAVA
	[T_COAL_ORE, T_COAL_ORE, T_COAL_ORE],         # COAL_ORE
	[T_PLANKS, T_PLANKS, T_PLANKS],               # PLANKS
	[T_ICE, T_ICE, T_ICE],                        # ICE
	[T_BASALT, T_BASALT, T_BASALT],               # BASALT
	[T_SANDSTONE_TOP, T_SANDSTONE, T_SANDSTONE_TOP], # SANDSTONE
	[T_COBBLESTONE, T_COBBLESTONE, T_COBBLESTONE],   # COBBLESTONE
]

static var _material: StandardMaterial3D
static var _far_material: StandardMaterial3D


## `far` = material for distant worlds: mipmapped so they don't shimmer.
static func get_material(far := false) -> StandardMaterial3D:
	if far:
		if _far_material == null:
			_far_material = _make_material(true)
		return _far_material
	if _material == null:
		_material = _make_material(false)
	return _material


static func _make_material(mipmaps: bool) -> StandardMaterial3D:
	var albedo := _build_atlas(false)
	var emission := _build_atlas(true)
	if mipmaps:
		albedo.generate_mipmaps()
		emission.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(albedo)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if mipmaps else BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.emission_enabled = true
	m.emission_texture = ImageTexture.create_from_image(emission)
	m.emission_energy_multiplier = 1.6
	return m


## UV rectangle (origin, size) of a tile in the atlas, in 0..1 space.
static func tile_uv_origin(tile: int) -> Vector2:
	return Vector2(float(tile % ATLAS_COLS) / ATLAS_COLS, float(tile / ATLAS_COLS) / ATLAS_ROWS)


static func tile_uv_size() -> Vector2:
	return Vector2(1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS)


# ---------------------------------------------------------------------------
# Procedural pixel art
# ---------------------------------------------------------------------------

static func _build_atlas(emission_only: bool) -> Image:
	var img := Image.create_empty(TILE * ATLAS_COLS, TILE * ATLAS_ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	for t in TILE_COUNT:
		rng.seed = 1000 + t * 7919
		var ox := (t % ATLAS_COLS) * TILE
		var oy := (t / ATLAS_COLS) * TILE
		for py in TILE:
			for px in TILE:
				var c := _tile_pixel(t, px, py, rng)
				if emission_only:
					c = c if t == T_LAVA else Color.BLACK
				img.set_pixel(ox + px, oy + py, c)
	return img


static func _hash(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), 1.0)


const _GRASS_C := Color(0.37, 0.63, 0.22)
const _DIRT_C := Color(0.53, 0.37, 0.23)
const _STONE_C := Color(0.5, 0.5, 0.52)
const _SAND_C := Color(0.87, 0.8, 0.56)
const _SNOW_C := Color(0.93, 0.95, 0.98)
const _BARK_C := Color(0.4, 0.29, 0.17)
const _COBBLE_SEEDS := [
	Vector2(2, 3), Vector2(8, 1), Vector2(13, 4), Vector2(5, 8), Vector2(11, 9),
	Vector2(1, 13), Vector2(7, 14), Vector2(14, 13), Vector2(15, 0), Vector2(0, 7),
]
const _ORE_SPOTS := [Vector2(3, 4), Vector2(10, 3), Vector2(6, 10), Vector2(12, 11), Vector2(2, 12)]


static func _tile_pixel(t: int, x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var n := rng.randf()
	match t:
		T_GRASS_TOP:
			return _shade(_GRASS_C, 0.8 + n * 0.35)
		T_GRASS_SIDE, T_SNOW_SIDE:
			var edge := 3 + int(_hash(x, 7.0) * 3.0)
			if y < edge:
				if t == T_GRASS_SIDE:
					return _shade(_GRASS_C, 0.8 + n * 0.3)
				return _shade(_SNOW_C, 0.92 + n * 0.08)
			return _shade(_DIRT_C, 0.75 + n * 0.4)
		T_DIRT:
			return _shade(_DIRT_C, 0.75 + n * 0.4)
		T_STONE:
			var streak := 0.85 if _hash(floor(x / 4.0) + y * 3.0, 2.0) < 0.12 else 1.0
			return _shade(_STONE_C, (0.85 + n * 0.25) * streak)
		T_SAND:
			return _shade(_SAND_C, 0.9 + n * 0.15)
		T_LOG_SIDE:
			var stripe := 0.78 if x % 4 == 0 else (0.9 if x % 4 == 2 else 1.0)
			return _shade(_BARK_C, (0.85 + n * 0.25) * stripe)
		T_LOG_TOP:
			var dist := Vector2(x - 7.5, y - 7.5).length()
			if dist > 6.5:
				return _shade(_BARK_C, 0.85 + n * 0.2)
			var ring := 0.85 if int(dist) % 2 == 0 else 1.0
			return _shade(Color(0.72, 0.56, 0.34), ring * (0.92 + n * 0.12))
		T_LEAVES:
			if n < 0.12:
				return _shade(Color(0.16, 0.36, 0.12), 0.8)
			return _shade(Color(0.22, 0.52, 0.17), 0.65 + n * 0.55)
		T_SNOW:
			return _shade(_SNOW_C, 0.92 + n * 0.08)
		T_WATER:
			var wave := 0.5 + 0.5 * sin(x * 0.8 + y * 0.45)
			return _shade(Color(0.17, 0.37, 0.78), 0.85 + wave * 0.2 + n * 0.06)
		T_LAVA:
			var blob := 0.5 + 0.5 * sin(x * 0.9 + sin(y * 0.7) * 2.0) * cos(y * 0.6 - x * 0.3)
			return Color(1.0, 0.3 + blob * 0.5 + n * 0.08, 0.05 + blob * 0.1, 1.0)
		T_COAL_ORE:
			for s in _ORE_SPOTS:
				if Vector2(x, y).distance_to(s) < 1.6:
					return _shade(Color(0.1, 0.1, 0.11), 0.8 + n * 0.4)
			return _shade(_STONE_C, 0.85 + n * 0.25)
		T_PLANKS:
			var board := y / 4
			var seam := (x + board * 5) % 16 == 0
			if y % 4 == 3 or seam:
				return _shade(Color(0.5, 0.36, 0.2), 0.9 + n * 0.1)
			return _shade(Color(0.72, 0.55, 0.33), 0.88 + n * 0.16)
		T_ICE:
			var s := 1.08 if (x + y) % 7 == 0 else 1.0
			return _shade(Color(0.62, 0.8, 0.95), (0.92 + n * 0.08) * s)
		T_BASALT:
			var band := 0.85 if y % 5 == 0 else 1.0
			return _shade(Color(0.24, 0.22, 0.25), (0.8 + n * 0.35) * band)
		T_SANDSTONE:
			var band2 := 0.88 if (y % 6 == 0 or y % 6 == 1) else 1.0
			return _shade(Color(0.85, 0.74, 0.5), (0.94 + n * 0.08) * band2)
		T_SANDSTONE_TOP:
			return _shade(Color(0.88, 0.78, 0.54), 0.95 + n * 0.06)
		T_COBBLESTONE:
			var d1 := 99.0
			var d2 := 99.0
			var cell := 0
			for i in _COBBLE_SEEDS.size():
				var d: float = Vector2(x, y).distance_to(_COBBLE_SEEDS[i])
				if d < d1:
					d2 = d1
					d1 = d
					cell = i
				elif d < d2:
					d2 = d
			if d2 - d1 < 1.0:
				return _shade(_STONE_C, 0.55 + n * 0.1)
			return _shade(_STONE_C, 0.85 + _hash(cell, 3.0) * 0.25 + n * 0.08)
	return Color.MAGENTA
