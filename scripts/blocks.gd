class_name Blocks
extends RefCounted
## Block ids, their colours, and the shared stylized block material.
##
## Visual style: no textures. Each block is a flat colour with a soft bevel on its
## edges, baked per-vertex ambient occlusion and slight per-block colour jitter.

const AIR := 0
const MOSS := 1
const SOIL := 2
const SLATE := 3
const SAND := 4
const TRUNK := 5
const FOLIAGE := 6
const SNOW := 7
const WATER := 8
const LAVA := 9
const CRYSTAL := 10
const PLANKS := 11
const ICE := 12
const BASALT := 13
const SANDSTONE := 14
const TILES := 15
const FOLIAGE_PEACH := 16
const FOLIAGE_MINT := 17
const FOLIAGE_LILAC := 18
const FOLIAGE_BUTTER := 19
const COUNT := 20

## Each tree picks one of these for its whole canopy.
const FOLIAGE_KINDS := [FOLIAGE, FOLIAGE_PEACH, FOLIAGE_MINT, FOLIAGE_LILAC, FOLIAGE_BUTTER]

const NAMES := [
	"Air", "Moss", "Soil", "Slate", "Sand", "Trunk", "Foliage", "Snow", "Water",
	"Lava", "Crystal", "Planks", "Ice", "Basalt", "Sandstone", "Tiles",
	"Peach Foliage", "Mint Foliage", "Lilac Foliage", "Butter Foliage",
]

## sRGB colours per block: [top, side, bottom]. "Top" faces point away from the planet centre.
const COLORS := [
	[Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)],                         # AIR
	[Color(0.33, 0.72, 0.58), Color(0.80, 0.50, 0.38), Color(0.80, 0.50, 0.38)], # MOSS (teal on terracotta)
	[Color(0.80, 0.50, 0.38), Color(0.80, 0.50, 0.38), Color(0.74, 0.45, 0.35)], # SOIL
	[Color(0.50, 0.56, 0.68), Color(0.47, 0.53, 0.65), Color(0.44, 0.49, 0.60)], # SLATE
	[Color(0.97, 0.86, 0.70), Color(0.95, 0.83, 0.67), Color(0.92, 0.80, 0.64)], # SAND
	[Color(0.78, 0.66, 0.56), Color(0.91, 0.85, 0.76), Color(0.78, 0.66, 0.56)], # TRUNK (cream bark)
	[Color(0.96, 0.56, 0.58), Color(0.93, 0.53, 0.56), Color(0.88, 0.49, 0.52)], # FOLIAGE (coral)
	[Color(0.96, 0.97, 1.00), Color(0.90, 0.92, 0.98), Color(0.80, 0.55, 0.45)], # SNOW
	[Color(0.30, 0.64, 0.92), Color(0.28, 0.60, 0.88), Color(0.26, 0.56, 0.84)], # WATER
	[Color(1.00, 0.48, 0.22), Color(1.00, 0.42, 0.20), Color(0.95, 0.38, 0.18)], # LAVA
	[Color(0.66, 0.46, 1.00), Color(0.62, 0.42, 0.98), Color(0.58, 0.40, 0.95)], # CRYSTAL
	[Color(0.93, 0.70, 0.46), Color(0.90, 0.67, 0.44), Color(0.86, 0.63, 0.41)], # PLANKS
	[Color(0.78, 0.92, 1.00), Color(0.74, 0.89, 0.99), Color(0.70, 0.86, 0.97)], # ICE
	[Color(0.30, 0.26, 0.36), Color(0.27, 0.24, 0.33), Color(0.25, 0.22, 0.30)], # BASALT
	[Color(0.93, 0.72, 0.52), Color(0.90, 0.69, 0.50), Color(0.86, 0.66, 0.48)], # SANDSTONE
	[Color(0.76, 0.78, 0.86), Color(0.72, 0.74, 0.83), Color(0.68, 0.70, 0.80)], # TILES
	[Color(0.98, 0.74, 0.47), Color(0.95, 0.71, 0.45), Color(0.90, 0.66, 0.42)], # FOLIAGE_PEACH
	[Color(0.45, 0.82, 0.70), Color(0.42, 0.79, 0.67), Color(0.39, 0.74, 0.63)], # FOLIAGE_MINT
	[Color(0.74, 0.62, 0.92), Color(0.71, 0.59, 0.89), Color(0.66, 0.55, 0.85)], # FOLIAGE_LILAC
	[Color(0.98, 0.85, 0.50), Color(0.95, 0.82, 0.48), Color(0.90, 0.77, 0.45)], # FOLIAGE_BUTTER
]

## How strongly a block glows (0 = not at all).
const GLOW := [0, 0, 0, 0, 0, 0, 0, 0, 0, 1.4, 0.9, 0, 0, 0, 0, 0, 0, 0, 0, 0]

const SHADER := """
shader_type spatial;
render_mode cull_back;

// UV  = position on the face (0..1), used for the soft bevel.
// UV2 = (glow strength, unused).
uniform float bevel_width = 0.09;
uniform float bevel_dark = 0.8;

void fragment() {
	vec2 e = min(UV, vec2(1.0) - UV);
	float edge = min(e.x, e.y);
	float aa = fwidth(edge);
	float bevel = mix(bevel_dark, 1.0, smoothstep(0.0, bevel_width + aa, edge));
	// Fade the bevel out when a block is only a few pixels big, to avoid shimmer.
	bevel = mix(bevel, 1.0, smoothstep(0.08, 0.25, aa));
	ALBEDO = COLOR.rgb * bevel;
	EMISSION = COLOR.rgb * UV2.x;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
"""

static var _material: ShaderMaterial
static var _linear_cache: Array = []


static func get_material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


## Must run on the main thread before any meshing (fills the colour cache).
static func init() -> void:
	if not _linear_cache.is_empty():
		return
	for id in COUNT:
		var row: Array = []
		for c in COLORS[id]:
			row.append(c.srgb_to_linear())
		_linear_cache.append(row)
	get_material()


static func _hash3(x: int, y: int, z: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h >> 8) & 0xFFFF) / 65535.0


## Linear colour of one face of a block at (x, y, z). kind: 0 top, 1 side, 2 bottom.
static func face_color(id: int, kind: int, x: int, y: int, z: int) -> Color:
	var c: Color = _linear_cache[id][kind]
	var j := 0.93 + _hash3(x, y, z) * 0.12
	return Color(c.r * j, c.g * j, c.b * j)
