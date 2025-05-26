@tool
class_name Blur extends Resource

@export var enable : bool = true
@export var use_double_pass : bool = true
@export var down_sample_level : int = 1

@export_group("Direct")
@export var radius : float = 0.01
@export var radial_quality : int = 4
@export var polar_quality : int = 5
@export var polar_shift : float = 0.3
@export var direct_weight_curve : Curve

@export_group("Double Pass")
@export var kernel_scale : float = 0.01
@export var kernel_size : int = 2
@export var horizontal_first : bool = true
@export var kernel_weight_curve : Curve

@export_group("Debug")
@export var blur_debug : bool = false
@export var blur_debug_layer : int = 1

func override(source : Blur) -> void:
	self.enable = source.enable
	self.use_double_pass = source.use_double_pass
	self.blur_debug = source.blur_debug
	self.blur_debug_layer = source.blur_debug_layer
	
	self.radius = source.radius
	self.radial_quality = source.radial_quality
	self.polar_quality = source.polar_quality
	self.polar_shift = source.polar_shift
	self.direct_weight_curve = source.direct_weight_curve
	
	self.kernel_scale = source.kernel_scale
	self.kernel_size = source.kernel_size
	self.kernel_weight_curve = source.kernel_weight_curve
	self.down_sample_level = source.down_sample_level
	self.horizontal_first = source.horizontal_first
	
	return
