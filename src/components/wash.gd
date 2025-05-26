class_name Wash extends Resource

@export var enable : bool = true

@export_group("Edge")
@export_range(0.0, 1.0) var edge_min : float = 0.1
@export_range(0.0, 1.0) var edge_max : float = 0.9
@export var edge_pow : float = 1.0

@export_group("Fill")
@export_range(0.0, 1.0) var fill_strength : float = 0.1
@export var fill_uv_scale : Vector2 = Vector2.ONE
@export var fill_uv_offset : Vector2 = Vector2.ZERO
@export var fill_uv_offset_shift : Vector2 = Vector2.ONE * 0.3
@export var fill_uv_offset_rot : float = 0.3


func override(source : Wash) -> void:
	self.enable = source.enable
	
	self.edge_min = source.edge_min
	self.edge_max = source.edge_max
	self.edge_pow = source.edge_pow
	
	return
