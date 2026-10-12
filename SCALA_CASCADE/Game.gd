extends Node3D
# SCALA CASCADE - nativo Godot 4.3. Sin WebView ni modelos GLB.
# Carrera lateral 3D con rescates, obstáculos, música y controles táctiles.
const SPEED := 5.3
const GRAVITY := 19.0
const JUMP := 8.3

var player: Node3D
var player_y := 0.0
var vertical_speed := 0.0
var playing := false
var score := 0
var rescued := 0
var elapsed := 0.0
var spawn_wait := 1.6
var chunks: Array = []
var objects: Array = []
var followers: Array = []
var palette: Dictionary = {}
var hud_label: Label
var menu: ColorRect
var heading: Label
var subheading: Label
var play_button: Button
var music: AudioStreamPlayer
var effect: AudioStreamPlayer

func _ready() -> void:
	randomize()
	_setup_camera()
	_setup_world()
	_setup_ui()
	_setup_audio()
	_show_home()

func _mat(color_code: String, luminous: bool = false) -> StandardMaterial3D:
	var id := color_code + (":light" if luminous else "")
	if palette.has(id):
		return palette[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.html(color_code)
	m.roughness = 0.76
	if luminous:
		m.emission_enabled = true
		m.emission = Color.html(color_code)
		m.emission_energy_multiplier = 1.5
	palette[id] = m
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, color_code: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _mat(color_code)
	node.position = at
	parent.add_child(node)
	return node

func _orb(parent: Node3D, size: Vector3, at: Vector3, color_code: String, luminous: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 16
	mesh.rings = 8
	node.mesh = mesh
	node.scale = size
	node.position = at
	node.material_override = _mat(color_code, luminous)
	parent.add_child(node)
	return node

func _cone(parent: Node3D, bottom: float, top: float, length: float, at: Vector3, color_code: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 9
	node.mesh = mesh
	node.position = at
	node.material_override = _mat(color_code)
	parent.add_child(node)
	return node

func _make_fox(main_color: String = "#ee9547", small: float = 1.0) -> Node3D:
	var fox := Node3D.new()
	fox.scale = Vector3.ONE * small
	# Silueta corporal, chaqueta, hocico, flequillo y pañuelo.
	_orb(fox, Vector3(0.80, 1.06, 0.62), Vector3(0, 0.94, 0), main_color)
	_orb(fox, Vector3(0.71, 0.76, 0.67), Vector3(0, 1.65, 0.08), main_color)
	_orb(fox, Vector3(0.50, 0.27, 0.38), Vector3(0, 1.43, 0.49), "#fff0cc")
	_orb(fox, Vector3(0.17, 0.13, 0.12), Vector3(0, 1.51, 0.71), "#56374a")
	_orb(fox, Vector3(0.16, 0.24, 0.11), Vector3(-0.18, 1.73, 0.402), "#ffffff")
	_orb(fox, Vector3(0.16, 0.24, 0.11), Vector3(0.18, 1.73, 0.402), "#ffffff")
	_orb(fox, Vector3(0.085, 0.15, 0.08), Vector3(-0.18, 1.73, 0.474), "#293951")
	_orb(fox, Vector3(0.085, 0.15, 0.08), Vector3(0.18, 1.73, 0.474), "#293951")
	_orb(fox, Vector3(0.04, 0.05, 0.05), Vector3(-0.205, 1.785, 0.518), "#ffffff")
	_orb(fox, Vector3(0.04, 0.05, 0.05), Vector3(0.155, 1.785, 0.518), "#ffffff")
	_cone(fox, 0.20, 0.016, 0.56, Vector3(-0.27, 2.17, 0.06), main_color).rotation_degrees.z = 16
	_cone(fox, 0.20, 0.016, 0.56, Vector3(0.27, 2.17, 0.06), main_color).rotation_degrees.z = -16
	_cone(fox, 0.12, 0.015, 0.35, Vector3(-0.27, 2.16, 0.18), "#ffcba4").rotation_degrees.z = 16
	_cone(fox, 0.12, 0.015, 0.35, Vector3(0.27, 2.16, 0.18), "#ffcba4").rotation_degrees.z = -16
	_orb(fox, Vector3(0.38, 0.28, 0.37), Vector3(-0.13, 1.96, 0.13), "#edba68")
	_orb(fox, Vector3(0.26, 0.16, 0.42), Vector3(0.08, 1.08, 0.26), "#ffe3ac")
	_cone(fox, 0.34, 0.32, 0.20, Vector3(0, 1.32, 0), "#43d2bf")
	var scarf_end := _box(fox, Vector3(0.19, 0.41, 0.12), Vector3(0.33, 1.07, 0.24), "#2eb4b0")
	scarf_end.rotation_degrees.z = 15
	# Cola afelpada articulada.
	var tail := Node3D.new()
	tail.position = Vector3(-0.41, 0.88, -0.23)
	fox.add_child(tail)
	_orb(tail, Vector3(0.85, 0.35, 0.37), Vector3(-0.35, 0.24, 0), main_color).rotation_degrees.z = -30
	_orb(tail, Vector3(0.35, 0.31, 0.35), Vector3(-0.68, 0.38, 0), "#fff1d9")
	fox.set_meta("tail", tail)
	# Brazos y piernas con pivotes para animación independiente.
	var left_arm := Node3D.new()
	left_arm.position = Vector3(-0.45, 1.20, 0)
	fox.add_child(left_arm)
	_orb(left_arm, Vector3(0.22, 0.54, 0.26), Vector3(-0.04, -0.22, 0), main_color)
	_orb(left_arm, Vector3(0.22, 0.22, 0.24), Vector3(-0.07, -0.48, 0.03), "#fff2d8")
	var right_arm := Node3D.new()
	right_arm.position = Vector3(0.45, 1.20, 0)
	fox.add_child(right_arm)
	_orb(right_arm, Vector3(0.22, 0.54, 0.26), Vector3(0.04, -0.22, 0), main_color)
	_orb(right_arm, Vector3(0.22, 0.22, 0.24), Vector3(0.07, -0.48, 0.03), "#fff2d8")
	var left_leg := Node3D.new()
	left_leg.position = Vector3(-0.21, 0.60, 0)
	fox.add_child(left_leg)
	_orb(left_leg, Vector3(0.25, 0.57, 0.28), Vector3(0, -0.22, 0), "#544970")
	_orb(left_leg, Vector3(0.31, 0.20, 0.45), Vector3(0, -0.50, 0.12), "#374768")
	var right_leg := Node3D.new()
	right_leg.position = Vector3(0.21, 0.60, 0)
	fox.add_child(right_leg)
	_orb(right_leg, Vector3(0.25, 0.57, 0.28), Vector3(0, -0.22, 0), "#544970")
	_orb(right_leg, Vector3(0.31, 0.20, 0.45), Vector3(0, -0.50, 0.12), "#374768")
	fox.set_meta("limbs", [left_arm, right_arm, left_leg, right_leg])
	return fox

func _setup_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.3
	cam.position = Vector3(0, 4.0, 19.5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#b5eaf4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8f6f0")
	env.ambient_light_energy = 0.85
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, -22)
	sun.light_energy = 1.0
	sun.shadow_enabled = false
	add_child(sun)
	# Plano cromático de cielo y colinas para dar profundidad.
	var back := Node3D.new()
	add_child(back)
	_box(back, Vector3(120, 8, 0.2), Vector3(0, 2, -15), "#9adcd6")
	for i in range(14):
		var k := float(i)
		_orb(back, Vector3(12, 7 + fmod(k * 3.1, 3), 0.7), Vector3(-42 + 8 * k, -0.3, -13.8), "#77cabb")
		_orb(back, Vector3(8, 5, 0.6), Vector3(-42 + 8 * k + 2, -0.8, -12.8), "#67bca9")
	_orb(back, Vector3(3.2, 3.2, 0.4), Vector3(5, 7, -14.2), "#fff0bc", true)
	for i in range(15):
		_orb(back, Vector3(0.15, 0.15, 0.15), Vector3(randf_range(-18, 18), randf_range(3.0, 7.0), -11.6), "#fffae7", true)

func _tree(parent: Node3D, at: Vector3, size: float) -> void:
	var n := Node3D.new()
	n.position = at
	n.scale = Vector3.ONE * size
	parent.add_child(n)
	_cone(n, 0.19, 0.13, 2.3, Vector3(0, 1.15, 0), "#795d6b")
	for i in range(4):
		_orb(n, Vector3(1.35, 1.30, 1.12), Vector3(-0.47 + float(i % 2) * 0.94, 2.20 + float(i / 2) * 0.55, (float(i % 2) - 0.5) * 0.25), "#369d83" if i % 2 == 0 else "#45b995")
	for i in range(3):
		_orb(n, Vector3(0.22, 0.22, 0.20), Vector3(randf_range(-0.65, 0.65), 2.3 + randf(), 0.70), "#f7c2da")

func _make_chunk(x: float) -> Node3D:
	var n := Node3D.new()
	n.position.x = x
	add_child(n)
	_box(n, Vector3(22, 0.85, 8), Vector3(0, -0.48, -0.25), "#53a77f")
	_box(n, Vector3(22, 0.06, 3.2), Vector3(0, -0.02, 0.6), "#e5ce94")
	_box(n, Vector3(22, 0.07, 0.17), Vector3(0, 0.03, -1.09), "#fff1bb")
	for j in range(9):
		var x_tree := -10 + float(j) * 2.65
		_tree(n, Vector3(x_tree, 0, -3.1 - float(j % 3) * 0.7), 0.70 + float(j % 3) * 0.16)
	for j in range(25):
		var gx := randf_range(-10.4, 10.4)
		var gz := randf_range(-3.3, -1.3)
		_cone(n, 0.065, 0.005, randf_range(0.25, 0.5), Vector3(gx, 0.16, gz), "#6cc58c")
		if j % 4 == 0:
			_orb(n, Vector3(0.15, 0.16, 0.16), Vector3(gx, 0.42, gz), "#ffe6a4" if j % 8 == 0 else "#f7a9cf")
	return n

func _setup_world() -> void:
	for x in [-22.0, 0.0, 22.0, 44.0]:
		chunks.append(_make_chunk(x))
	player = _make_fox()
	player.position = Vector3(-3, 0, 0.6)
	add_child(player)

func _make_object(kind: String) -> void:
	var n := Node3D.new()
	n.position = Vector3(12.0, 0.0, 0.6)
	n.set_meta("kind", kind)
	add_child(n)
	if kind == "crystal":
		_orb(n, Vector3(0.48, 0.75, 0.46), Vector3(0, 1.10, 0), "#fff7d2", true)
		_cone(n, 0.32, 0.0, 0.75, Vector3(0, 1.58, 0), "#eafc9c")
		_cone(n, 0.0, 0.32, 0.49, Vector3(0, 0.61, 0), "#d2ef7d")
	elif kind == "friend":
		var friend := _make_fox("#b7a6f1", 0.82)
		friend.position.y = 0.1
		n.add_child(friend)
		n.set_meta("friend_model", friend)
	else:
		_cone(n, 0.51, 0.32, 1.12, Vector3(0, 0.53, 0), "#7c5a79")
		_orb(n, Vector3(0.26, 0.24, 0.16), Vector3(-0.20, 0.78, 0.31), "#fa7181", true)
		_orb(n, Vector3(0.26, 0.24, 0.16), Vector3(0.20, 0.78, 0.31), "#fa7181", true)
		_cone(n, 0.24, 0.0, 0.35, Vector3(-0.33, 1.17, 0), "#8b6387")
		_cone(n, 0.24, 0.0, 0.35, Vector3(0.33, 1.17, 0), "#8b6387")
	objects.append(n)

func _animate_fox(fox: Node3D, t: float, intensity: float) -> void:
	if not fox.has_meta("limbs"):
		return
	var limbs: Array = fox.get_meta("limbs")
	var p := sin(t * 12.0) * intensity
	limbs[0].rotation.z = p * 0.52
	limbs[1].rotation.z = -p * 0.52
	limbs[2].rotation.z = -p * 0.65
	limbs[3].rotation.z = p * 0.65
	var tail: Node3D = fox.get_meta("tail")
	tail.rotation.z = -0.18 + sin(t * 6.1) * 0.19

func _process(delta: float) -> void:
	elapsed += delta
	_animate_fox(player, elapsed, 0.18 if not playing else 1.0)
	if not playing:
		return
	score += int(delta * 75.0 + 0.5)
	vertical_speed -= GRAVITY * delta
	player_y = maxf(0.0, player_y + vertical_speed * delta)
	if player_y <= 0.001:
		vertical_speed = maxf(0.0, vertical_speed)
	player.position.y = player_y + sin(elapsed * 13.0) * 0.035 if player_y == 0.0 else player_y
	for c in chunks:
		c.position.x -= SPEED * delta
		if c.position.x < -40:
			c.position.x += 88
	spawn_wait -= delta
	if spawn_wait < 0.0:
		spawn_wait = maxf(1.15, 2.0 - float(score) * 0.00007)
		var roll := randi_range(0, 9)
		_make_object("crystal" if roll < 5 else "friend" if roll < 8 else "obstacle")
	for obj in objects.duplicate():
		obj.position.x -= SPEED * delta
		if obj.get_meta("kind") == "crystal":
			obj.rotation.y += delta * 2.4
			obj.position.y = sin(elapsed * 4.0) * 0.14
		elif obj.get_meta("kind") == "friend":
			_animate_fox(obj.get_meta("friend_model"), elapsed + obj.position.x, 0.5)
		if obj.position.x < -14:
			objects.erase(obj)
			obj.queue_free()
			continue
		if absf(obj.position.x - player.position.x) < 0.62:
			var kind: String = obj.get_meta("kind")
			if kind == "obstacle" and player_y < 0.74:
				_hit()
				objects.erase(obj)
				obj.queue_free()
			elif kind != "obstacle":
				if kind == "friend":
					_rescue()
				else:
					score += 100
					_beep(1.25)
				objects.erase(obj)
				obj.queue_free()
	for i in range(followers.size()):
		var ally: Node3D = followers[i]
		ally.position.x = -3.0 - float(i + 1) * 0.82
		ally.position.y = maxf(0.0, sin(elapsed * 3.0 - float(i) * 0.35) * 0.13)
		_animate_fox(ally, elapsed - float(i) * 0.23, 0.8)
	hud_label.text = "✦ %06d       AMIGOS %02d" % [score, followers.size() + 1]

func _rescue() -> void:
	rescued += 1
	score += 250
	var ally := _make_fox("#b7a6f1" if rescued % 2 == 0 else "#8fdbca", 0.72)
	ally.position = Vector3(-4, 0, 0.6)
	add_child(ally)
	followers.append(ally)
	_beep(1.65)

func _hit() -> void:
	_beep(0.43)
	if followers.size() > 0:
		var ally: Node3D = followers.pop_back()
		ally.queue_free()
	else:
		playing = false
		heading.text = "FIN DE LA AVENTURA"
		subheading.text = "PUNTOS: %d     RESCATADOS: %d" % [score, rescued]
		play_button.text = "INTENTAR DE NUEVO"
		menu.visible = true

func _jump() -> void:
	if playing and player_y < 0.015:
		vertical_speed = JUMP
		_beep(1.02)

func _input(event: InputEvent) -> void:
	if not playing:
		return
	if event is InputEventScreenTouch and event.pressed:
		_jump()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_UP, KEY_W]:
			_jump()

func _show_home() -> void:
	playing = false
	heading.text = "SCALA CASCADE"
	subheading.text = "CORRE  ·  SALTA  ·  RESCATA A TUS AMIGOS"
	play_button.text = "INICIAR AVENTURA"
	menu.visible = true

func _start_game() -> void:
	for obj in objects:
		obj.queue_free()
	objects.clear()
	for ally in followers:
		ally.queue_free()
	followers.clear()
	playing = true
	score = 0
	rescued = 0
	player_y = 0.0
	vertical_speed = 0.0
	player.position.y = 0
	spawn_wait = 1.6
	menu.visible = false
	if not music.playing:
		music.play()

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var top := ColorRect.new()
	top.color = Color(0.09, 0.22, 0.27, 0.73)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 73
	root.add_child(top)
	hud_label = Label.new()
	hud_label.position = Vector2(40, 15)
	hud_label.size = Vector2(940, 50)
	hud_label.text = "✦ 000000       AMIGOS 01"
	hud_label.add_theme_font_size_override("font_size", 30)
	hud_label.add_theme_color_override("font_color", Color("#fff8d2"))
	top.add_child(hud_label)
	var hint := Label.new()
	hint.text = "TOCA LA PANTALLA PARA SALTAR"
	hint.add_theme_font_size_override("font_size", 23)
	hint.add_theme_color_override("font_color", Color("#fffde0"))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_top = -65
	hint.offset_bottom = -25
	root.add_child(hint)
	menu = ColorRect.new()
	menu.color = Color(0.035, 0.115, 0.17, 0.84)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	heading = Label.new()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", Color("#ffe5ac"))
	heading.anchor_left = 0.03
	heading.anchor_right = 0.97
	heading.anchor_top = 0.24
	heading.anchor_bottom = 0.24
	heading.offset_bottom = 90
	menu.add_child(heading)
	subheading = Label.new()
	subheading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subheading.add_theme_font_size_override("font_size", 26)
	subheading.add_theme_color_override("font_color", Color("#dafff1"))
	subheading.anchor_left = 0.05
	subheading.anchor_right = 0.95
	subheading.anchor_top = 0.48
	subheading.anchor_bottom = 0.48
	subheading.offset_bottom = 54
	menu.add_child(subheading)
	play_button = Button.new()
	play_button.text = "INICIAR AVENTURA"
	play_button.add_theme_font_size_override("font_size", 30)
	play_button.anchor_left = 0.31
	play_button.anchor_right = 0.69
	play_button.anchor_top = 0.67
	play_button.anchor_bottom = 0.67
	play_button.offset_bottom = 79
	play_button.pressed.connect(_start_game)
	menu.add_child(play_button)
	var footer := Label.new()
	footer.text = "SCALA GAMES  ·  PRIMERA MISIÓN 3D"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 20)
	footer.add_theme_color_override("font_color", Color("#b5e2d3"))
	footer.anchor_left = 0.2
	footer.anchor_right = 0.8
	footer.anchor_top = 0.88
	footer.offset_bottom = 30
	menu.add_child(footer)

func _tone_stream(freq_scale: float = 1.0, notes: int = 16) -> AudioStreamWAV:
	var rate := 22050
	var samples := rate * 4 if notes > 8 else rate / 4
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var tune := [262.0, 330.0, 392.0, 523.0, 392.0, 330.0, 294.0, 392.0, 440.0, 523.0, 587.0, 523.0, 440.0, 392.0, 330.0, 294.0]
	for i in range(samples):
		var sec := float(i) / float(rate)
		var unit := int(sec * 4.0)
		var hz := float(tune[unit % tune.size()]) * freq_scale
		var envelope := 0.65 + 0.35 * (1.0 - fmod(sec * 4.0, 1.0))
		var v := (sin(sec * TAU * hz) * 0.23 + sin(sec * TAU * hz * 0.5) * 0.07) * envelope
		var sample := clampi(int(v * 32767.0), -32768, 32767)
		if sample < 0:
			sample += 65536
		pcm[i * 2] = sample & 255
		pcm[i * 2 + 1] = (sample >> 8) & 255
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = pcm
	if notes > 8:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples
	return wav

func _setup_audio() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -17
	music.stream = _tone_stream()
	add_child(music)
	effect = AudioStreamPlayer.new()
	effect.volume_db = -8
	effect.stream = _tone_stream(1.0, 1)
	add_child(effect)

func _beep(scale_value: float) -> void:
	effect.stream = _tone_stream(scale_value, 1)
	effect.play()
