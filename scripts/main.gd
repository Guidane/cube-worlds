extends Node3D
## Sets up the environment, the playable cube world, the worlds in the sky, the player and the HUD.

## Other cube worlds floating in the sky. Positions are relative to the home world's centre,
## spread out so some are visible from every face.
const SKY_WORLDS := [
	{"biome": "desert", "seed": 11, "pos": Vector3(290, 110, -80)},
	{"biome": "snow", "seed": 22, "pos": Vector3(-260, 150, 150)},
	{"biome": "lava", "seed": 33, "pos": Vector3(120, -270, 210)},
	{"biome": "ocean", "seed": 44, "pos": Vector3(-170, -160, -280)},
	{"biome": "grass", "seed": 55, "pos": Vector3(70, 340, 80)},
	{"biome": "ocean", "seed": 66, "pos": Vector3(320, -100, 250)},
	{"biome": "desert", "seed": 77, "pos": Vector3(-120, 60, 360)},
	{"biome": "lava", "seed": 88, "pos": Vector3(-340, -40, -60)},
	{"biome": "snow", "seed": 99, "pos": Vector3(60, -330, -120)},
	{"biome": "grass", "seed": 111, "pos": Vector3(150, 200, -300)},
]

const SKY_SHADER := """
shader_type sky;

uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 zenith_color : source_color = vec3(0.24, 0.30, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.98, 0.78, 0.70);
uniform vec3 nadir_color : source_color = vec3(0.50, 0.42, 0.66);

void sky() {
	float h = dot(EYEDIR, normalize(up_dir));
	vec3 col = h > 0.0
		? mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.6))
		: mix(horizon_color, nadir_color, pow(clamp(-h, 0.0, 1.0), 0.6));
	if (LIGHT0_ENABLED) {
		float s = dot(EYEDIR, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * smoothstep(0.9990, 0.9995, s) * 4.0;
		col += LIGHT0_COLOR * pow(max(s, 0.0), 64.0) * 0.35;
	}
	COLOR = col;
}
"""

var home_world: VoxelWorld
var player: Player
var sky_material: ShaderMaterial

var _loading_label: Label
var _block_label: Label
var _screenshot_path := ""


func _ready() -> void:
	_setup_input()
	_setup_environment()
	_setup_hud()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.trim_prefix("--screenshot=")

	home_world = VoxelWorld.new()
	home_world.name = "HomeWorld"
	home_world.biome = "grass"
	home_world.world_seed = 1234
	add_child(home_world)
	home_world.generated.connect(_on_home_generated)
	home_world.generate_async()

	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in SKY_WORLDS.size():
		var cfg: Dictionary = SKY_WORLDS[i]
		var w := VoxelWorld.new()
		w.name = "SkyWorld_%d_%s" % [i, cfg.biome]
		w.biome = cfg.biome
		w.world_seed = cfg.seed
		w.with_collision = false
		w.position = cfg.pos
		w.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		w.spin_axis = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		w.spin_speed = rng.randf_range(0.015, 0.05)
		add_child(w)
		w.generate_async()

	player = Player.new()
	player.name = "Player"
	player.world = home_world
	add_child(player)
	player.selection_changed.connect(func(n: String) -> void: _block_label.text = n)


func _on_home_generated() -> void:
	player.spawn()
	_loading_label.visible = false
	_block_label.text = Blocks.NAMES[Player.HOTBAR[player.selected]]
	if _screenshot_path.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_take_screenshots()


func _process(_delta: float) -> void:
	if player and player.is_inside_tree():
		sky_material.set_shader_parameter("up_dir", player.global_transform.basis.y)


# ---------------------------------------------------------------------------

func _setup_input() -> void:
	var map := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"descend": [KEY_CTRL, KEY_C],
		"sprint": [KEY_SHIFT],
		"toggle_fly": [KEY_F],
		"respawn": [KEY_R],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var shader := Shader.new()
	shader.code = SKY_SHADER
	sky_material = ShaderMaterial.new()
	sky_material.shader = shader
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.68, 0.85)
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.92, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -Vector3(0.45, 1.0, 0.3), Vector3.FORWARD)

	# Soft fill light from the opposite side so the far faces of the cube aren't pitch black.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.45, 1.0, 0.3), Vector3.FORWARD)


func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var cross := Control.new()
	cross.custom_minimum_size = Vector2(20, 20)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(cross)
	for r in [Rect2(9, 0, 2, 20), Rect2(0, 9, 20, 2)]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.85)
		bar.position = r.position
		bar.size = r.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cross.add_child(bar)

	var help := Label.new()
	help.text = "WASD move · Space jump · Shift sprint · Mouse look\nLMB break · RMB place · 1-9 / wheel select block\nF fly (Space/Ctrl up/down) · R respawn · Esc release mouse"
	help.position = Vector2(12, 10)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 4)
	layer.add_child(help)

	_block_label = Label.new()
	_block_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_block_label.position.y -= 50
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_block_label.add_theme_font_size_override("font_size", 22)
	_block_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_block_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_block_label)

	_loading_label = Label.new()
	_loading_label.text = "Generating worlds..."
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_label.add_theme_font_size_override("font_size", 32)
	_loading_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_loading_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_loading_label)


# Debug: `godot --path . -- --screenshot=out.png` saves a few views and quits.
func _take_screenshots() -> void:
	await get_tree().create_timer(6.0).timeout  # let sky worlds finish generating
	player.head.rotation.x = -0.35
	await _save_shot("")
	player.rotate_object_local(Vector3.UP, 0.6)
	player.head.rotation.x = 0.45
	await _save_shot("_sky")

	# Overview of the whole planet from a distance.
	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)
	cam.look_at_from_position(Vector3(95, 70, 110), Vector3.ZERO, Vector3.UP)
	cam.make_current()
	await _save_shot("_overview")
	player.camera.make_current()
	cam.queue_free()

	# Walk test: start on the top face, walk toward +X over the edge and onto the +X face.
	var col := Vector3i(32 + 14, 0, 32)
	for y in range(63, -1, -1):
		col.y = y
		if home_world.get_block(col) != Blocks.AIR:
			break
	player.global_transform = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP),
		home_world.to_global(home_world.block_center_local(col) + Vector3(0, 1.5, 0)))
	player.velocity = Vector3.ZERO
	player.grav_up = Vector3.UP
	player.head.rotation.x = -0.5
	Input.action_press("move_forward")
	Input.action_press("jump")
	for i in 7:
		await get_tree().create_timer(0.5).timeout
		print("walk t=%.1f pos=%s up=%s floor=%s" % [i * 0.5, home_world.to_local(player.global_position).snapped(Vector3.ONE * 0.1), player.grav_up, player.is_on_floor()])
	Input.action_release("jump")
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		print("walk t=%.1f pos=%s up=%s floor=%s" % [3.5 + i * 0.5, home_world.to_local(player.global_position).snapped(Vector3.ONE * 0.1), player.grav_up, player.is_on_floor()])
	Input.action_release("move_forward")
	await get_tree().create_timer(1.0).timeout
	await _save_shot("_walk")
	get_tree().quit()


func _save_shot(suffix: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_screenshot_path.get_basename() + suffix + ".png")
