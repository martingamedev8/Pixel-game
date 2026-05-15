extends CharacterBody2D

## Folder name under `res://characters/<folder>/` where sprites live, e.g. `warrior` → `warrior_n.png`, …
@export var character_folder: String = "warrior"
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
## Seconds per idle animation frame while standing still.
@export var idle_frame_duration: float = 0.20
## Seconds per walk frame while moving.
@export var walk_frame_duration: float = 0.085
## West walk (and east when it mirrors west): multiplied into `walk_frame_duration` (lower = faster leg cycle; 1 = same as other directions). Does not change movement `speed`.
@export_range(0.2, 1.0, 0.01) var west_walk_frame_duration_scale: float = 0.50
## Time for one 90° turn strip.
@export var turn_duration: float = 0.30

@export_group("Brightness (matches idle vs attack)")
## Multiplies colours on the idle sprite. Usually leave white.
@export var idle_modulate: Color = Color.WHITE
## If the attack PNG looks hotter/brighter than idle, darken slightly, e.g. (0.82, 0.82, 0.82).
@export var attack_modulate: Color = Color.WHITE

const _DIR_N := &"n"
const _DIR_S := &"s"
const _DIR_E := &"e"
const _DIR_W := &"w"
const _DIR_KEYS: Array[StringName] = [_DIR_N, _DIR_S, _DIR_E, _DIR_W]

@onready var body_sprite: Sprite2D = $BodySprite
@onready var placeholder: ColorRect = $DebugPlayerPlaceholder

## Last movement-facing compass key: n, s, e, w (screen: up, down, right, left).
var _facing: StringName = _DIR_S
## Idle texture per direction (same keys as above).
var _idle_textures: Dictionary = {}
## Idle animation frames per direction (same keys as above).
var _idle_animation_textures: Dictionary = {}
var _idle_anim_time := 0.0
var _idle_anim_frame_index := -1
var _idle_anim_facing: StringName = &""
## Walking frames per direction (same keys as above).
var _walk_textures: Dictionary = {}
var _walk_time := 0.0
var _walk_frame_index := -1
var _walk_facing: StringName = &""
## True when east uses the same walk strip as west with `Sprite2D.flip_h`.
var _east_walk_mirrors_west := false

## attack 1 → 2 → 3 in order while E attack is active
var _attack_frames: Array[Texture2D] = []
var _attack_frame_index := -1

var _attacking := false
var _attack_time_left := 0.0
var _cooldown_left := 0.0
var _e_key_was_down := false

var _turn_playing := false
var _turn_time_left := 0.0
var _turn_textures: Array[Texture2D] = []
var _turn_frame_index := -1
## Destination facing for the strip currently playing (idle at end of this turn).
var _turn_target: StringName = _DIR_S
## When input changes to another facing mid-turn, we finish the current strip then play this next.
var _has_queued_turn := false
var _queued_want: StringName = _DIR_S

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


func _character_texture_path(suffix: String) -> String:
	return "res://characters/%s/%s_%s.png" % [character_folder, character_folder, suffix]


func _character_animation_path(folder: String, base: String, frame: int) -> String:
	return "res://characters/%s/%s/%s_%02d.png" % [character_folder, folder, base, frame]


func _facing_from_direction(dir: Vector2) -> StringName:
	if dir == Vector2.ZERO:
		return _facing
	# Screen space: −Y is north, +Y south. Prefer E/W when |dx| ≥ |dy|.
	if absf(dir.x) >= absf(dir.y):
		return _DIR_E if dir.x > 0.0 else _DIR_W
	return _DIR_S if dir.y > 0.0 else _DIR_N


func _apply_idle_visual(facing: StringName) -> void:
	if not is_instance_valid(body_sprite):
		return
	if not _idle_textures.has(facing):
		return
	var tex: Texture2D = _idle_textures[facing]
	body_sprite.texture = tex
	body_sprite.scale = _sprite_scale_for_height(tex)
	body_sprite.modulate = idle_modulate
	body_sprite.flip_h = false


func _reset_idle_animation() -> void:
	_idle_anim_time = 0.0
	_idle_anim_frame_index = -1
	_idle_anim_facing = &""


func _apply_idle_animation(facing: StringName, delta: float) -> void:
	if not is_instance_valid(body_sprite):
		return
	if not _idle_animation_textures.has(facing):
		_apply_idle_visual(facing)
		return

	var frames: Array = _idle_animation_textures[facing]
	if frames.is_empty():
		_apply_idle_visual(facing)
		return

	if _idle_anim_facing != facing:
		_idle_anim_time = 0.0
		_idle_anim_frame_index = -1
		_idle_anim_facing = facing
	else:
		_idle_anim_time += delta

	var frame_duration := maxf(0.04, idle_frame_duration)
	var idx := int(_idle_anim_time / frame_duration) % frames.size()
	if idx == _idle_anim_frame_index:
		return
	_idle_anim_frame_index = idx
	var tex := frames[idx] as Texture2D
	if tex == null:
		return
	body_sprite.texture = tex
	body_sprite.scale = _sprite_scale_for_height(tex)
	body_sprite.modulate = idle_modulate
	body_sprite.flip_h = false


func _reset_walk_animation() -> void:
	_walk_time = 0.0
	_walk_frame_index = -1
	_walk_facing = &""


func _apply_walk_visual(facing: StringName, delta: float) -> void:
	if not is_instance_valid(body_sprite):
		return
	if not _walk_textures.has(facing):
		_apply_idle_visual(facing)
		return

	var frames: Array = _walk_textures[facing]
	if frames.is_empty():
		_apply_idle_visual(facing)
		return

	if _walk_facing != facing:
		_walk_time = 0.0
		_walk_frame_index = -1
		_walk_facing = facing
	else:
		_walk_time += delta

	var per_frame := walk_frame_duration
	if facing == _DIR_W or (facing == _DIR_E and _east_walk_mirrors_west):
		per_frame *= west_walk_frame_duration_scale
	var frame_duration := maxf(0.03, per_frame)
	var idx := int(_walk_time / frame_duration) % frames.size()
	if idx == _walk_frame_index:
		return
	_walk_frame_index = idx
	var tex := frames[idx] as Texture2D
	if tex == null:
		return
	body_sprite.texture = tex
	body_sprite.scale = _sprite_scale_for_height(tex)
	body_sprite.modulate = idle_modulate
	body_sprite.flip_h = facing == _DIR_E and _east_walk_mirrors_west


func _dir_letter(d: StringName) -> String:
	match String(d):
		"n":
			return "N"
		"s":
			return "S"
		"e":
			return "E"
		"w":
			return "W"
		_:
			return ""


func _is_adjacent_facing(a: StringName, b: StringName) -> bool:
	if a == b:
		return false
	if (a == _DIR_N and b == _DIR_S) or (a == _DIR_S and b == _DIR_N):
		return false
	if (a == _DIR_E and b == _DIR_W) or (a == _DIR_W and b == _DIR_E):
		return false
	return true


func _turn_strip_base(from_d: StringName, to_d: StringName) -> String:
	if not _is_adjacent_facing(from_d, to_d):
		return ""
	var a := String(from_d)
	var b := String(to_d)
	if a.is_empty() or b.is_empty():
		return ""
	return "turn_%s_to_%s" % [a, b]


func _load_numbered_animation_frames(folder: String, base: String, max_frames: int = 16) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for i in range(1, max_frames + 1):
		var path := _character_animation_path(folder, base, i)
		if not ResourceLoader.exists(path):
			break
		var tex := load(path) as Texture2D
		if tex == null:
			push_warning("player.gd: failed to load %s (reimport in Godot)." % path)
			continue
		frames.append(
			_cutout_border_connected_background(tex) if apply_background_cutout else tex
		)
	return frames


func _try_begin_turn(from_d: StringName, to_d: StringName) -> bool:
	var base := _turn_strip_base(from_d, to_d)
	if base.is_empty():
		return false
	var frames := _load_numbered_animation_frames("turns", base, 8)
	if frames.is_empty():
		return false
	_turn_target = to_d
	_has_queued_turn = false
	_turn_textures = frames
	_turn_playing = true
	_turn_time_left = maxf(0.06, turn_duration)
	_turn_frame_index = -1
	_reset_idle_animation()
	_reset_walk_animation()
	_apply_turn_frame(0.0)
	return true


func _apply_turn_frame(elapsed: float) -> void:
	var n := _turn_textures.size()
	if n <= 0 or not is_instance_valid(body_sprite):
		return
	var seg := maxf(0.06, turn_duration) / float(n)
	var idx := clampi(int(elapsed / seg), 0, n - 1)
	if idx == _turn_frame_index:
		return
	_turn_frame_index = idx
	var tex := _turn_textures[idx]
	body_sprite.texture = tex
	body_sprite.scale = _sprite_scale_for_height(tex)
	body_sprite.modulate = idle_modulate
	body_sprite.flip_h = false


func _finish_turn(dir: Vector2) -> void:
	_turn_playing = false
	_turn_time_left = 0.0
	_turn_frame_index = -1
	_turn_textures.clear()
	_facing = _turn_target
	_apply_idle_visual(_facing)

	var next_want: StringName
	if _has_queued_turn:
		next_want = _queued_want
		_has_queued_turn = false
	else:
		next_want = _facing_from_direction(dir)

	if next_want != _facing:
		if _try_begin_turn(_facing, next_want):
			_facing = next_want
		else:
			_facing = next_want
			_apply_idle_visual(_facing)


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

	if body_sprite.material != null:
		body_sprite.material = null

	for dir_key in _DIR_KEYS:
		var path := _character_texture_path(String(dir_key))
		if not ResourceLoader.exists(path):
			push_warning("player.gd: missing idle sprite %s" % path)
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			push_warning("player.gd: failed to load %s (reimport in Godot)." % path)
			continue
		var shown: Texture2D = (
			_cutout_border_connected_background(tex) if apply_background_cutout else tex
		)
		_idle_textures[dir_key] = shown

		var idle_base := "idle_%s" % String(dir_key)
		var idle_frames := _load_numbered_animation_frames("idle", idle_base, 16)
		if not idle_frames.is_empty():
			_idle_animation_textures[dir_key] = idle_frames

		var walk_base := "walk_%s" % String(dir_key)
		var walk_frames := _load_numbered_animation_frames("walk", walk_base, 16)
		if not walk_frames.is_empty():
			_walk_textures[dir_key] = walk_frames

	# East walk: reuse west strip with horizontal flip if no `walk_e_*` files exist.
	if _walk_textures.has(_DIR_W) and not _walk_textures.has(_DIR_E):
		_walk_textures[_DIR_E] = _walk_textures[_DIR_W]
		_east_walk_mirrors_west = true

	if _idle_textures.is_empty():
		push_error(
			"player.gd: no idle sprites in res://characters/%s/ — expected %s_n/e/s/w.png."
			% [character_folder, character_folder]
		)
		if is_instance_valid(placeholder):
			placeholder.visible = true
		return

	if not _idle_textures.has(_facing):
		_facing = _idle_textures.keys()[0]

	_apply_idle_visual(_facing)
	if is_instance_valid(placeholder):
		placeholder.visible = false

	var attack_paths := PackedStringArray([
		_character_texture_path("attack_1"),
		_character_texture_path("attack_2"),
		_character_texture_path("attack_3"),
	])
	for ap in attack_paths:
		if not ResourceLoader.exists(ap):
			continue
		var atk := load(ap) as Texture2D
		if atk == null:
			push_warning("player.gd: failed to load %s (reimport in Godot)." % ap)
			continue
		_attack_frames.append(
			_cutout_border_connected_background(atk) if apply_background_cutout else atk
		)
	if _attack_frames.size() > 0 and _attack_frames.size() < 3:
		push_warning(
			"player.gd: need all three %s_attack_1/2/3.png for the slash combo (optional)."
			% character_folder
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
	body_sprite.flip_h = false

func _try_begin_attack() -> void:
	if _attack_frames.is_empty() or _idle_textures.is_empty():
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
	_reset_idle_animation()
	_reset_walk_animation()
	_apply_idle_visual(_facing)
	_cooldown_left = attack_cooldown

func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)

	var e_down := Input.is_physical_key_pressed(KEY_E)
	var e_just := e_down and not _e_key_was_down
	_e_key_was_down = e_down
	if Input.is_action_just_pressed("attack") or e_just:
		if _turn_playing:
			_turn_playing = false
			_turn_time_left = 0.0
			_turn_textures.clear()
			_turn_frame_index = -1
			_has_queued_turn = false
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

	if _turn_playing:
		if dir != Vector2.ZERO:
			var want_while_turn := _facing_from_direction(dir)
			if want_while_turn != _turn_target:
				_has_queued_turn = true
				_queued_want = want_while_turn
			else:
				_has_queued_turn = false
		var elapsed_turn := turn_duration - _turn_time_left
		_apply_turn_frame(elapsed_turn)
		_turn_time_left -= delta
		if _turn_time_left <= 0.0:
			_finish_turn(dir)
		velocity = dir * speed
		move_and_slide()
		return

	if dir != Vector2.ZERO:
		_reset_idle_animation()
		var want := _facing_from_direction(dir)
		if want != _facing:
			var old_facing := _facing
			if _try_begin_turn(old_facing, want):
				_facing = want
			else:
				_facing = want
				_apply_idle_visual(_facing)
		if not _turn_playing:
			_apply_walk_visual(_facing, delta)
	else:
		if _walk_frame_index != -1:
			_reset_walk_animation()
		_apply_idle_animation(_facing, delta)

	velocity = dir * speed
	move_and_slide()
