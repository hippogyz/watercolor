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
@export var fill_noise_tex : Texture2D

@export_group("Border")
@export_range(0.0, 1.0) var border_strength : float = 0.1
@export var border_uv_scale : Vector2 = Vector2.ONE
@export var border_uv_offset : Vector2 = Vector2.ZERO
@export var border_uv_offset_shift : Vector2 = Vector2.ONE * 0.3
@export var border_uv_offset_rot : float = 0.3
@export var border_noise_tex : Texture2D


func override(source : Wash) -> void:
	self.enable = source.enable
	
	self.edge_min = source.edge_min
	self.edge_max = source.edge_max
	self.edge_pow = source.edge_pow
	
	self.fill_strength = source.fill_strength
	self.fill_uv_scale = source.fill_uv_scale
	self.fill_uv_offset = source.fill_uv_offset
	self.fill_uv_offset_shift = source.fill_uv_offset_shift
	self.fill_uv_offset_rot = source.fill_uv_offset_rot
	self.fill_noise_tex = source.fill_noise_tex
	
	self.border_strength = source.border_strength
	self.border_uv_scale = source.border_uv_scale
	self.border_uv_offset = source.border_uv_offset
	self.border_uv_offset_shift = source.border_uv_offset_shift
	self.border_uv_offset_rot = source.border_uv_offset_rot
	self.border_noise_tex = source.border_noise_tex
	
	return
