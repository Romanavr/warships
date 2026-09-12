class_name ShipSystem
extends RefCounted
## One independently damageable component. Fire intensity is 0..1.
var id: String
var label: String
var maximum: float
var health: float
var fire: float = 0.0
var position: Vector3
var size: Vector3
var compartment: String
var hull: bool = false
var disabled_reported: bool = false

func _init(key: String, title: String, hp: float, point: Vector3, bounds: Vector3, room: String, is_hull: bool = false) -> void:
	id = key
	label = title
	maximum = hp
	health = hp
	position = point
	size = bounds
	compartment = room
	hull = is_hull

func fraction() -> float:
	return health / maximum

func working() -> bool:
	return health > 0.0
