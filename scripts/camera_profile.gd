class_name CameraProfile extends Resource

@export var distance := 4.0
@export var shoulder := 0.0
@export var height := 0.0
@export var fov := 75.0

static func create(d: float, s: float, h: float, f: float) -> CameraProfile:
	var p := CameraProfile.new()
	p.distance = d
	p.shoulder = s
	p.height = h
	p.fov = f
	return p
