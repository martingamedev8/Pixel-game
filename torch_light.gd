extends PointLight2D

## Relative swing around the inspector `energy` (0.12 ≈ ±12%).
@export var flicker_strength: float = 0.09
## How fast the flame drifts (rad/s combined with inner sines).
@export var flicker_speed: float = 3.8

var _base_energy: float
var _phase: float


func _ready() -> void:
	_base_energy = energy
	_phase = randf() * TAU


func _physics_process(delta: float) -> void:
	_phase += delta * flicker_speed
	var wobble: float = (
		sin(_phase) * 0.55
		+ sin(_phase * 2.17 + 1.3) * 0.32
		+ sin(_phase * 5.9 + 0.7) * 0.13
	)
	energy = _base_energy * (1.0 + flicker_strength * clampf(wobble, -1.0, 1.0))
