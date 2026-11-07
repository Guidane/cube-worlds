class_name Player
extends CharacterBody3D
## First-person player that can walk on every face of a cube world.
## Gravity points toward the face the player is over; the body smoothly
## re-orients when crossing an edge.

signal selection_changed(block_name: String)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const FLY_SPEED := 12.0
const JUMP_VELOCITY := 8.0
const GRAVITY := 24.0
const MOUSE_SENSITIVITY := 0.0025
const TURN_RATE := 8.0
const REACH := 6.0
const HOTBAR := [
	Blocks.MOSS, Blocks.SOIL, Blocks.SLATE, Blocks.TILES, Blocks.PLANKS,
	Blocks.TRUNK, Blocks.FOLIAGE, Blocks.SAND, Blocks.SNOW,
]

var world: VoxelWorld
var grav_up := Vector3.UP
var flying := false
var selected := 0

var head: Node3D
var camera: Camera3D
var _highlight: MeshInstance3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	add_child(shape)

	head = Node3D.new()
	head.position = Vector3(0, 0.65, 0)
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 4000.0
	head.add_child(camera)
	camera.make_current()

	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.2
	_highlight = _make_highlight()
	add_child(_highlight)
	_highlight.top_level = true
	_highlight.visible = false


func spawn() -> void:
	# Stand on top of the column at the centre of the +Y face.
	var col := Vector3i(int(VoxelWorld.HALF), 0, int(VoxelWorld.HALF))
	var top := 0
	for y in range(VoxelWorld.SIZE - 1, -1, -1):
		col.y = y
		if world.get_block(col) != Blocks.AIR:
			top = y
			break
	var local := world.block_center_local(Vector3i(col.x, top, col.z)) + Vector3(0, 0.5 + 0.95, 0)
	grav_up = world.global_transform.basis.y
	global_transform = Transform3D(Basis(), world.to_global(local))
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_object_local(Vector3.UP, -event.relative.x * MOUSE_SENSITIVITY)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.55, 1.55)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_break_block()
			MOUSE_BUTTON_RIGHT:
				_place_block()
			MOUSE_BUTTON_WHEEL_UP:
				_select((selected - 1 + HOTBAR.size()) % HOTBAR.size())
			MOUSE_BUTTON_WHEEL_DOWN:
				_select((selected + 1) % HOTBAR.size())
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_select(event.keycode - KEY_1)
		elif event.is_action("toggle_fly"):
			flying = not flying
		elif event.is_action("respawn"):
			spawn()


func _select(i: int) -> void:
	selected = clampi(i, 0, HOTBAR.size() - 1)
	selection_changed.emit(Blocks.NAMES[HOTBAR[selected]])


func _physics_process(delta: float) -> void:
	if world == null or not world.is_generated:
		return
	grav_up = world.gravity_up(global_position, grav_up)
	_align_to(grav_up, delta)
	var b := global_transform.basis
	var up := b.y
	up_direction = up

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := (b.x * input.x + b.z * input.y)
	var vert := velocity.dot(up)
	var horiz := velocity - up * vert

	if flying:
		var v_in := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("descend"))
		vert = move_toward(vert, v_in * FLY_SPEED, 60.0 * delta)
		horiz = horiz.lerp(wish * FLY_SPEED, clampf(10.0 * delta, 0.0, 1.0))
	else:
		var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
		if is_on_floor():
			vert = maxf(vert, 0.0)
			if Input.is_action_pressed("jump"):
				vert = JUMP_VELOCITY
		vert -= GRAVITY * delta
		var accel := 14.0 if is_on_floor() else 4.0
		horiz = horiz.lerp(wish * speed, clampf(accel * delta, 0.0, 1.0))

	velocity = horiz + up * vert
	move_and_slide()

	if world.to_local(global_position).length() > 150.0:
		spawn()


func _process(_delta: float) -> void:
	_update_highlight()


func _align_to(target: Vector3, delta: float) -> void:
	var cur := global_transform.basis.y
	var ang := cur.angle_to(target)
	if ang < 0.0005:
		return
	var axis := cur.cross(target)
	if axis.length_squared() < 1e-8:
		axis = global_transform.basis.x
	axis = axis.normalized()
	var step := minf(ang, maxf(TURN_RATE * delta * ang, 2.5 * delta))
	global_transform.basis = (Basis(axis, step) * global_transform.basis).orthonormalized()


# ---------------------------------------------------------------------------
# Block interaction
# ---------------------------------------------------------------------------

func _look_ray() -> Dictionary:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	return world.raycast(origin, dir, REACH)


func _break_block() -> void:
	var hit := _look_ray()
	if not hit.is_empty():
		world.set_block(hit.pos, Blocks.AIR)


func _place_block() -> void:
	var hit := _look_ray()
	if hit.is_empty():
		return
	var p: Vector3i = hit.prev
	if world.get_block(p) != Blocks.AIR and world.get_block(p) != Blocks.WATER:
		return
	if _overlaps_player(p):
		return
	world.set_block(p, HOTBAR[selected])


func _overlaps_player(p: Vector3i) -> bool:
	var local_center := world.to_local(global_position)
	var local_up := (world.global_transform.basis.inverse() * global_transform.basis.y).normalized()
	var ext := Vector3(0.3, 0.3, 0.3) + local_up.abs() * 0.6
	var player_box := AABB(local_center - ext, ext * 2.0)
	var block_box := AABB(Vector3(p) - Vector3(VoxelWorld.HALF, VoxelWorld.HALF, VoxelWorld.HALF), Vector3.ONE)
	return player_box.intersects(block_box)


func _update_highlight() -> void:
	if world == null or not world.is_generated or camera == null:
		_highlight.visible = false
		return
	var hit := _look_ray()
	if hit.is_empty():
		_highlight.visible = false
		return
	_highlight.visible = true
	var center := world.block_center_local(hit.pos)
	_highlight.global_transform = world.global_transform * Transform3D(Basis().scaled(Vector3.ONE * 1.004), center)


func _make_highlight() -> MeshInstance3D:
	var pts := PackedVector3Array()
	var c := [
		Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5), Vector3(-0.5, -0.5, 0.5),
		Vector3(-0.5, 0.5, -0.5), Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
	]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		pts.append(c[e[0]])
		pts.append(c[e[1]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 1)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
