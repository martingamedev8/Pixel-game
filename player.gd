extends CharacterBody2D

@export var speed: float = 140.0
## World-space height for idle/attack sprites after scaling (e.g. 64 ≈ two 32×32 floor tiles tall).
@export var sprite_height_units: float = 64.0
## If true, flood-fills transparency from image edges using colors similar to the border.
## Black/dark armour can match dark vignettes; tune cutout_rgb_threshold / dark_protect or export a PNG with real alpha instead.
@export var apply_background_cutout: bool = false
## Max RGB distance to the nearest border pixel (roughly max ~1.73). Lower = keep more of the character, may leave more backdrop.
@export var cutout_rgb_threshold: float = 0.11
## Pixels darker than (darkest border tone minus this) are treated as foreground and never removed.
@export var cutout_dark_protect: float = 0.03
## Pixels more saturated than this are never removed (keeps cape, gold trim, skin).
@export var cutout_max_bg_saturation: float = 0.06

## Total time for all 3 attack frames (lower = snappier slash).
@export var attack_duration: float = 0.18
## Hold E continuously to swing again immediately after cooldown.
@export var attack_cooldown: float = 0.03

@export_group("Brightness (matches idle vs attack)")
## Multiplies colours on the idle sprite. Usually leave white.
@export var idle_modulate: Color = Color.WHITE
## If the attack PNG looks hotter/brighter than idle, darken slightly, e.g. (0.82, 0.82, 0.82).
@export var attack_modulate: Color = Color.WHITE

@onready var body_sprite: Sprite2D = $BodySprite
@onready var placeholder: ColorRect = $DebugPlayerPlaceholder

var _idle_tex: Texture2D
var _idle_scale: Vector2 = Vector2.ONE

## attack 1 → 2 → 3 in order while E attack is active
var _attack_frames: Array[Texture2D] = []
var _attack_frame_index := -1

var _attacking := false
var _attack_time_left := 0.0
var _cooldown_left := 0.0
var _e_key_was_down := false

func _ensure_attack_input() -> void:
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var has_e := false
	for ev in InputMap.action_get_events("attack"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_E:
			has_e = true
			break
	if not has_e:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_E
		InputMap.action_add_event("attack", key)

func _max_channel(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b))

func _saturation(c: Color) -> float:
	return _max_channel(c) - minf(c.r, minf(c.g, c.b))

func _min_dist_to_bg_rgb(c: Color, bg_samples: PackedColorArray) -> float:
	var best := 999.0
	for b in bg_samples:
		var d := Vector3(c.r, c.g, c.b).distance_to(Vector3(b.r, b.g, b.b))
		if d < best:
			best = d
	return best

func _collect_border_samples(img: Image, w: int, h: int, step: int) -> Dictionary:
	var samples := PackedColorArray()
	var border_min_maxc := 1.0
	var border_max_maxc := 0.0

	for x in range(0, w, step):
		for y in [0, h - 1]:
			var p := img.get_pixel(x, y)
			var mx := _max_channel(p)
			border_min_maxc = minf(border_min_maxc, mx)
			border_max_maxc = maxf(border_max_maxc, mx)
			samples.append(p)
	for y in range(0, h, step):
		for x in [0, w - 1]:
			var p2 := img.get_pixel(x, y)
			var mx2 := _max_channel(p2)
			border_min_maxc = minf(border_min_maxc, mx2)
			border_max_maxc = maxf(border_max_maxc, mx2)
			samples.append(p2)

	return {"samples": samples, "border_min_maxc": border_min_maxc, "border_max_maxc": border_max_maxc}

func _cutout_border_connected_background(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	img.convert(Image.FORMAT_RGBA8)

	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return tex

	var step := maxi(1, mini(w, h) / 128)
	var border := _collect_border_samples(img, w, h, step)
	var bg_samples: PackedColorArray = border["samples"]
	var border_min_maxc: float = border["border_min_maxc"]

	# Work on raw bytes for speed: RGBA8 => 4 bytes per pixel.
	var data: PackedByteArray = img.get_data()
	var visited := PackedByteArray()
	visited.resize(w * h)

	# Queue stored as PackedInt32Array of flattened indices to avoid tuple overhead.
	var q := PackedInt32Array()
	q.resize(0)
	q.append(0)
	q.append(w - 1)
	q.append((h - 1) * w)
	q.append((h - 1) * w + (w - 1))
	for x in range(w):
		q.append(x)
		q.append((h - 1) * w + x)
	for y in range(h):
		q.append(y * w)
		q.append(y * w + (w - 1))

	var threshold := cutout_rgb_threshold
	var dark_floor := border_min_maxc - cutout_dark_protect

	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1

		if visited[i] != 0:
			continue
		visited[i] = 1

		var x := i % w
		var y := i / w

		var o := i * 4
		var c := Color(
			float(data[o]) / 255.0,
			float(data[o + 1]) / 255.0,
			float(data[o + 2]) / 255.0,
			float(data[o + 3]) / 255.0
		)
		if c.a == 0.0:
			pass
		else:
			var mx := _max_channel(c)
			# Armour/shadow often darker than vignette strips that touch the silhouette.
			if mx < dark_floor:
				continue
			if _saturation(c) > cutout_max_bg_saturation:
				continue
			if _min_dist_to_bg_rgb(c, bg_samples) > threshold:
				continue

		data[o + 3] = 0

		if x > 0:
			q.append(i - 1)
		if x < w - 1:
			q.append(i + 1)
		if y > 0:
			q.append(i - w)
		if y < h - 1:
			q.append(i + w)

	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	var out := ImageTexture.create_from_image(img)
	return out

func _ready() -> void:
	_ensure_attack_input()
	if not is_instance_valid(body_sprite):
		push_error("Player: expected a Sprite2D child named BodySprite.")
		if is_instance_valid(placeholder):
			placeholder.visible = true
		return
	# If you place your provided character image at res://player.png,
	# it will be used automatically.
	if ResourceLoader.exists("res://player.png"):
		var tex := load("res://player.png") as Texture2D
		if tex != null:
			# Remove any material-based keying; we'll cut out into alpha instead.
			if body_sprite.material != null:
				body_sprite.material = null
			if apply_background_cutout:
				body_sprite.texture = _cutout_border_connected_background(tex)
			else:
				body_sprite.texture = tex
			# Auto-scale textures so the image height matches sprite_height_units in the world.
			var h := float(tex.get_height())
			if h > 0.0:
				var s := sprite_height_units / h
				body_sprite.scale = Vector2(s, s)
			_idle_tex = body_sprite.texture
			_idle_scale = body_sprite.scale
			body_sprite.modulate = idle_modulate
			if is_instance_valid(placeholder):
				placeholder.visible = false
		else:
			if is_instance_valid(placeholder):
				placeholder.visible = true
	else:
		if is_instance_valid(placeholder):
			placeholder.visible = true

	var attack_paths := PackedStringArray([
		"res://player_attack_1.png",
		"res://player_attack_2.png",
		"res://player_attack_3.png",
	])
	for ap in attack_paths:
		if not ResourceLoader.exists(ap):
			push_warning("player.gd: missing %s — add attack 1/2/3 PNGs to the project." % ap)
			continue
		var atk := load(ap) as Texture2D
		if atk == null:
			push_warning("player.gd: failed to load %s (Reimport in Godot)." % ap)
			continue
		_attack_frames.append(
			_cutout_border_connected_background(atk) if apply_background_cutout else atk
		)
	if _attack_frames.size() < 3:
		push_warning(
			"player.gd: need all three res://player_attack_1.png … _3.png for the slash combo."
		)

func _sprite_scale_for_height(tex: Texture2D) -> Vector2:
	var hh := float(tex.get_height())
	if hh <= 0.0:
		return Vector2.ONE
	var s := sprite_height_units / hh
	return Vector2(s, s)

func _apply_attack_frame(elapsed: float) -> void:
	var n := _attack_frames.size()
	if n <= 0:
		return
	var seg := attack_duration / float(n)
	var idx := clampi(int(elapsed / seg), 0, n - 1)
	if idx == _attack_frame_index:
		return
	_attack_frame_index = idx
	var tex := _attack_frames[idx]
	body_sprite.texture = tex
	body_sprite.scale = _sprite_scale_for_height(tex)

func _try_begin_attack() -> void:
	if _attack_frames.is_empty() or _idle_tex == null:
		return
	if _attacking:
		return
	if _cooldown_left > 0.0:
		return
	_attacking = true
	_attack_time_left = maxf(0.045, attack_duration)
	_attack_frame_index = -1
	var elapsed0 := 0.0
	_apply_attack_frame(elapsed0)
	body_sprite.modulate = attack_modulate

func _finish_attack() -> void:
	_attacking = false
	_attack_time_left = 0.0
	_attack_frame_index = -1
	body_sprite.texture = _idle_tex
	body_sprite.scale = _idle_scale
	body_sprite.modulate = idle_modulate
	_cooldown_left = attack_cooldown

func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var e_down := Input.is_physical_key_pressed(KEY_E)
	var e_just := e_down and not _e_key_was_down
	_e_key_was_down = e_down
	if Input.is_action_just_pressed("attack") or e_just:
		_try_begin_attack()

	if _attacking:
		var elapsed := attack_duration - _attack_time_left
		_apply_attack_frame(elapsed)
		_attack_time_left -= delta
		if _attack_time_left <= 0.0:
			_finish_attack()
		else:
			velocity = Vector2.ZERO
			move_and_slide()
		return

	# Explicit WASD — ui_up/ui_down often only bind to arrow keys unless you edit the Input Map.
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()

	velocity = dir * speed
	move_and_slide()
