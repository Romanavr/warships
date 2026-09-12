class_name ShipLoadout
extends Resource
## Editable hull and weapon tuning shared by both teams. Runtime health is separate.
@export var designation: String = "Kestrel-class missile corvette"
## Which hull to build. Empty means the corvette mesh, scaled to `length`.
@export var hull_model: String = ""
## Kit this class was never fitted with. Those modules start at zero health,
## their meshes are hidden, and neither repair path brings them back. It is how
## a fast attack craft differs from the corvette, and how an unarmed hull is
## expressed at all.
@export var offline_by_design: Array[String] = []
## A civilian hull: no magazine to cook off, no mounts to blow away, and no
## supply crate when she goes down.
@export var civilian: bool = false
@export var length: float = 54.0
@export var beam: float = 10.0
@export var speed: float = 16.5
@export var gun_range: float = 600.0
@export var missile_range: float = 1400.0
@export var missile_reload: float = 8.0
@export var ciws_range: float = 190.0
@export var ciws_rounds: int = 120
@export var component_health: Dictionary = {
	"bow": 280.0, "mid": 420.0, "stern": 300.0,
	"gun": 115.0, "aft_gun": 95.0, "engine": 210.0, "rudder": 70.0,
	"bridge": 145.0, "radar": 65.0, "launcher_port": 100.0,
	"launcher_starboard": 100.0, "ciws": 85.0, "sam": 100.0
}
