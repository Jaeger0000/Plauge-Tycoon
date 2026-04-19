class_name FactoryData

const MACHINES := {
	"Basic": {"cost": 100, "sterilize_speed": 1.0, "cutting_speed": 1.0, "packaging_speed": 1.0, "color": Color(0.6, 0.6, 0.6), "sprite": "res://sprites/basic.png"},
	"Alpha": {"cost": 150, "sterilize_speed": 0.5, "cutting_speed": 1.2, "packaging_speed": 1.5, "color": Color(0.9, 0.3, 0.3), "sprite": "res://sprites/ster.png"},
	"Beta": {"cost": 150, "sterilize_speed": 1.5, "cutting_speed": 0.5, "packaging_speed": 1.2, "color": Color(0.3, 0.6, 0.9), "sprite": "res://sprites/cut.png"},
	"Gamma": {"cost": 150, "sterilize_speed": 1.2, "cutting_speed": 1.5, "packaging_speed": 0.5, "color": Color(0.3, 0.9, 0.3), "sprite": "res://sprites/pack.png"},
	"Omega": {"cost": 300, "sterilize_speed": 0.7, "cutting_speed": 0.7, "packaging_speed": 0.7, "color": Color(0.9, 0.8, 0.2), "sprite": "res://sprites/legend.png"},
}

const FURNITURE := {
	"Chair": {"base_sterilize_time": 3.0, "base_cut_time": 4.0, "base_package_time": 2.0, "grid_w": 2, "grid_h": 2, "color": Color(0.65, 0.4, 0.2)},
	"Table": {"base_sterilize_time": 5.0, "base_cut_time": 6.0, "base_package_time": 3.0, "grid_w": 3, "grid_h": 2, "color": Color(0.45, 0.28, 0.12)},
	"Shelf": {"base_sterilize_time": 2.0, "base_cut_time": 3.0, "base_package_time": 2.0, "grid_w": 1, "grid_h": 3, "color": Color(0.72, 0.55, 0.35)},
	"Stool": {"base_sterilize_time": 2.0, "base_cut_time": 2.0, "base_package_time": 1.0, "grid_w": 1, "grid_h": 2, "color": Color(0.55, 0.35, 0.18)},
}

const STAGE_RAW := 0
const STAGE_STERILIZED := 1
const STAGE_CUT := 2
const STAGE_PACKAGED := 3


static func get_stage_color(stage: int, furniture_type: String) -> Color:
	match stage:
		STAGE_RAW:
			return Color(0.55, 0.36, 0.2)
		STAGE_STERILIZED:
			return Color(0.75, 0.58, 0.38)
		STAGE_CUT:
			if FURNITURE.has(furniture_type):
				return FURNITURE[furniture_type]["color"]
			return Color(0.6, 0.4, 0.2)
		STAGE_PACKAGED:
			var base_col := Color(0.6, 0.4, 0.2)
			if FURNITURE.has(furniture_type):
				base_col = FURNITURE[furniture_type]["color"]
			return base_col.lerp(Color(0.78, 0.62, 0.44), 0.5)
	return Color.WHITE


static func get_process_time(furniture_type: String, stage_name: String, machine_type: String) -> float:
	var fdata: Dictionary = FURNITURE[furniture_type]
	var mdata: Dictionary = MACHINES[machine_type]
	var base_time := 5.0
	var speed := 1.0
	match stage_name:
		"sterilize":
			base_time = fdata["base_sterilize_time"]
			speed = mdata["sterilize_speed"]
		"cutting":
			base_time = fdata["base_cut_time"]
			speed = mdata["cutting_speed"]
		"packaging":
			base_time = fdata["base_package_time"]
			speed = mdata["packaging_speed"]
	return base_time * speed
