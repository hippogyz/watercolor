class_name Wash extends Resource

@export var enable : bool = true

@export_group("Edge")
@export_range(0.0, 1.0) var edge_min : float = 0.1
@export_range(0.0, 1.0) var edge_max : float = 0.9
@export var edge_pow : float = 1.0


func override(source : Wash) -> void:
	self.enable = source.enable
	
	self.edge_min = source.edge_min
	self.edge_max = source.edge_max
	self.edge_pow = source.edge_pow
	
	return
