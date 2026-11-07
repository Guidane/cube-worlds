class_name VoxelWorld
extends Node3D
## A 64x64x64 cube world. The node's origin is the centre of the cube.
## Block (x, y, z) occupies local space [x - 32, x - 31) on each axis.

signal generated

const SIZE := WorldGenerator.SIZE
const HALF := WorldGenerator.HALF
const CHUNK := 16
const NCH := SIZE / CHUNK
const DIRS := WorldGenerator.DIRS
const GRAVITY_HYSTERESIS := 0.4

@export var biome := "grass"
@export var world_seed := 1
@export var with_collision := true
@export var spin_speed := 0.0
@export var spin_axis := Vector3.UP

var blocks := PackedByteArray()
var is_generated := false
var _chunks := {}  # Vector3i -> Node3D (MeshInstance3D, optionally with a StaticBody3D child)

# Static lookup tables (built once on the main thread before any meshing).
static var _tables_ready := false
static var _face_corners: Array = []     # [face] -> Array[Vector3] (4 corners, clockwise from outside)
static var _face_uvs: Array = []         # [up][face] -> PackedVector2Array (4 local uvs)
static var _face_kind: Array = []        # [up][face] -> 0 top, 1 side, 2 bottom


class MeshBuffers:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var inds := PackedInt32Array()


func _process(delta: float) -> void:
	if spin_speed != 0.0:
		rotate(spin_axis.normalized(), spin_speed * delta)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

func generate_async() -> void:
	VoxelWorld.init_tables()
	Blocks.get_material(not with_collision)
	WorkerThreadPool.add_task(_thread_generate.bind(biome, world_seed))


func _thread_generate(p_biome: String, p_seed: int) -> void:
	var gen := WorldGenerator.new(p_biome, p_seed)
	var data := gen.generate()
	var meshes := {}
	for cz in NCH:
		for cy in NCH:
			for cx in NCH:
				var c := Vector3i(cx, cy, cz)
				meshes[c] = VoxelWorld.build_chunk_arrays(data, c)
	_finish_generation.call_deferred(data, meshes)


func _finish_generation(data: PackedByteArray, meshes: Dictionary) -> void:
	blocks = data
	for c in meshes:
		_apply_chunk(c, meshes[c])
	is_generated = true
	generated.emit()


func _apply_chunk(c: Vector3i, arrays: Array) -> void:
	if _chunks.has(c):
		_chunks[c].queue_free()
		_chunks.erase(c)
	if arrays.is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Blocks.get_material(not with_collision))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Chunk_%d_%d_%d" % [c.x, c.y, c.z]
	if with_collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	add_child(mi)
	_chunks[c] = mi


func rebuild_chunk(c: Vector3i) -> void:
	_apply_chunk(c, VoxelWorld.build_chunk_arrays(blocks, c))


# ---------------------------------------------------------------------------
# Block access
# ---------------------------------------------------------------------------

func get_block(p: Vector3i) -> int:
	if not WorldGenerator.in_bounds(p) or blocks.is_empty():
		return Blocks.AIR
	return blocks[WorldGenerator.idx(p)]


func set_block(p: Vector3i, id: int) -> bool:
	if not WorldGenerator.in_bounds(p) or blocks.is_empty():
		return false
	blocks[WorldGenerator.idx(p)] = id
	var c := Vector3i(p.x / CHUNK, p.y / CHUNK, p.z / CHUNK)
	rebuild_chunk(c)
	for a in 3:
		var e := Vector3i()
		e[a] = 1
		if p[a] % CHUNK == 0 and c[a] > 0:
			rebuild_chunk(c - e)
		elif p[a] % CHUNK == CHUNK - 1 and c[a] < NCH - 1:
			rebuild_chunk(c + e)
	return true


## Local-space centre of a block.
func block_center_local(p: Vector3i) -> Vector3:
	return Vector3(p) - Vector3(HALF, HALF, HALF) + Vector3(0.5, 0.5, 0.5)


func block_at_local(local: Vector3) -> Vector3i:
	var v := local + Vector3(HALF, HALF, HALF)
	return Vector3i(floori(v.x), floori(v.y), floori(v.z))


## Voxel DDA raycast. Returns {} on miss, or {"pos": Vector3i, "prev": Vector3i, "normal": Vector3i}.
func raycast(from_global: Vector3, dir_global: Vector3, max_dist: float) -> Dictionary:
	var o := to_local(from_global) + Vector3(HALF, HALF, HALF)
	var d := (global_transform.basis.inverse() * dir_global).normalized()
	var v := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for a in 3:
		if absf(d[a]) < 1e-9:
			t_max[a] = INF
			t_delta[a] = INF
		else:
			var next_edge := float(v[a] + (1 if step[a] > 0 else 0))
			t_max[a] = (next_edge - o[a]) / d[a]
			t_delta[a] = absf(1.0 / d[a])
	var prev := v
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(v)
		if id != Blocks.AIR and id != Blocks.WATER and id != Blocks.LAVA:
			return {"pos": v, "prev": prev, "normal": normal}
		prev = v
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		v[a] += step[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
		t = t_max[a]
		t_max[a] += t_delta[a]
	return {}


## Unit vector (global space) pointing "up" for something at `global_pos`:
## the outward normal of the cube face it is over. `current` gives hysteresis
## so gravity doesn't flicker when standing right on an edge.
func gravity_up(global_pos: Vector3, current: Vector3) -> Vector3:
	var o := to_local(global_pos)
	var a := o.abs()
	var best: Vector3
	var m: float = max(a.x, a.y, a.z)
	if a.y >= m:
		best = Vector3(0, signf(o.y), 0)
	elif a.x >= m:
		best = Vector3(signf(o.x), 0, 0)
	else:
		best = Vector3(0, 0, signf(o.z))
	var cur_local := (global_transform.basis.inverse() * current).round()
	if cur_local.length_squared() == 1.0 and o.dot(cur_local) >= m - GRAVITY_HYSTERESIS:
		best = cur_local
	return (global_transform.basis * best).normalized()


# ---------------------------------------------------------------------------
# Meshing
# ---------------------------------------------------------------------------

static func init_tables() -> void:
	if _tables_ready:
		return
	_face_corners.clear()
	for f in 6:
		var n: Vector3i = DIRS[f]
		var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
		var side := 1.0 if n[axis] > 0 else 0.0
		var t1 := (axis + 1) % 3
		var t2 := (axis + 2) % 3
		var corners: Array = []
		for q in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			var c := Vector3()
			c[axis] = side
			c[t1] = q.x
			c[t2] = q.y
			corners.append(c)
		# Godot treats clockwise triangles (seen from the front) as front faces.
		var cr: Vector3 = (corners[1] - corners[0]).cross(corners[2] - corners[0])
		if cr.dot(Vector3(n)) > 0.0:
			corners.reverse()
		_face_corners.append(corners)

	_face_uvs.clear()
	_face_kind.clear()
	for u in 6:
		var uv_row: Array = []
		var kind_row: Array = []
		var up := Vector3(DIRS[u])
		for f in 6:
			var n := Vector3(DIRS[f])
			var kind := 1
			var u_axis: Vector3
			var v_axis: Vector3
			if f == u:
				kind = 0
			elif n == -up:
				kind = 2
			if kind == 1:
				u_axis = up.cross(n)   # screen-right when looking at the face, up = block up
				v_axis = -up           # texture v grows downward
			else:
				var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
				u_axis = Vector3()
				v_axis = Vector3()
				u_axis[(axis + 1) % 3] = 1.0
				v_axis[(axis + 2) % 3] = 1.0
			var uvs := PackedVector2Array()
			for c in _face_corners[f]:
				var uu: float = c.dot(u_axis) + (1.0 if (u_axis.x + u_axis.y + u_axis.z) < 0.0 else 0.0)
				var vv: float = c.dot(v_axis) + (1.0 if (v_axis.x + v_axis.y + v_axis.z) < 0.0 else 0.0)
				uvs.append(Vector2(uu, vv))
			uv_row.append(uvs)
			kind_row.append(kind)
		_face_uvs.append(uv_row)
		_face_kind.append(kind_row)
	_tables_ready = true


## Which face of the planet a block belongs to (index into DIRS).
static func up_index(x: int, y: int, z: int) -> int:
	var ox := x + 0.5 - HALF
	var oy := y + 0.5 - HALF
	var oz := z + 0.5 - HALF
	var ax := absf(ox)
	var ay := absf(oy)
	var az := absf(oz)
	if ay >= ax and ay >= az:
		return 2 if oy > 0.0 else 3
	if ax >= az:
		return 0 if ox > 0.0 else 1
	return 4 if oz > 0.0 else 5


static func build_chunk_arrays(data: PackedByteArray, c: Vector3i) -> Array:
	var b := MeshBuffers.new()
	var S := SIZE
	var S2 := SIZE * SIZE
	var x0 := c.x * CHUNK
	var y0 := c.y * CHUNK
	var z0 := c.z * CHUNK
	for z in range(z0, z0 + CHUNK):
		for y in range(y0, y0 + CHUNK):
			for x in range(x0, x0 + CHUNK):
				var i := x + y * S + z * S2
				var id := data[i]
				if id == 0:
					continue
				var e0 := x == S - 1 or data[i + 1] == 0
				var e1 := x == 0 or data[i - 1] == 0
				var e2 := y == S - 1 or data[i + S] == 0
				var e3 := y == 0 or data[i - S] == 0
				var e4 := z == S - 1 or data[i + S2] == 0
				var e5 := z == 0 or data[i - S2] == 0
				if not (e0 or e1 or e2 or e3 or e4 or e5):
					continue
				var u := up_index(x, y, z)
				var base := Vector3(x - HALF, y - HALF, z - HALF)
				if e0: _emit_face(b, base, 0, id, u)
				if e1: _emit_face(b, base, 1, id, u)
				if e2: _emit_face(b, base, 2, id, u)
				if e3: _emit_face(b, base, 3, id, u)
				if e4: _emit_face(b, base, 4, id, u)
				if e5: _emit_face(b, base, 5, id, u)
	if b.verts.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.verts
	arrays[Mesh.ARRAY_NORMAL] = b.norms
	arrays[Mesh.ARRAY_TEX_UV] = b.uvs
	arrays[Mesh.ARRAY_COLOR] = b.cols
	arrays[Mesh.ARRAY_INDEX] = b.inds
	return arrays


const _SHADE := [1.0, 0.82, 0.62]  # top, side, bottom
const _UV_EPS := 0.002


static func _emit_face(b: MeshBuffers, base: Vector3, f: int, id: int, u: int) -> void:
	var kind: int = _face_kind[u][f]
	var tile: int = Blocks.FACE_TILES[id][kind]
	var origin := Blocks.tile_uv_origin(tile)
	var size := Blocks.tile_uv_size()
	var corners: Array = _face_corners[f]
	var luv: PackedVector2Array = _face_uvs[u][f]
	var n := Vector3(DIRS[f])
	var shade: float = _SHADE[kind]
	if kind == 1 and (f & 1) == 1:
		shade *= 0.92
	var col := Color(shade, shade, shade)
	var start := b.verts.size()
	for k in 4:
		b.verts.append(base + corners[k])
		b.norms.append(n)
		var l := luv[k]
		var cl := Vector2(lerpf(_UV_EPS, 1.0 - _UV_EPS, l.x), lerpf(_UV_EPS, 1.0 - _UV_EPS, l.y))
		b.uvs.append(origin + cl * size)
		b.cols.append(col)
	b.inds.append(start)
	b.inds.append(start + 1)
	b.inds.append(start + 2)
	b.inds.append(start)
	b.inds.append(start + 2)
	b.inds.append(start + 3)
