@tool
class_name CircleOverrideScreen extends CompositorEffect

@export var radius : float = 0.3
@export var repeat : float = 5.0
@export var inside_color : Color = Color(1.0, 1.0, 1.0)
@export var outside_color : Color = Color(0.0, 0.0, 0.0)

var _rd : RenderingDevice
var _need_clean : Array[RID] = []
const GROUP_SIZE : Vector3i = Vector3i(8, 8, 1)

const SHADER_PATH : String = "res://shaders/circle_override_screen.glsl"
var _shader : RID
var _pipeline : RID
var _int_params : RID
var _float_params : RID

func _init() -> void:
	self.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	self._rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(self._init_runtime)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _rd == null:
			return
		
		_need_clean.reverse()
		for _rid : RID in _need_clean:
			_rd.free_rid(_rid)
		_need_clean.clear()
		
		_rd = null
	
	return

func _init_runtime() -> void:
	if self._rd == null:
		return
	
	self._shader = self._rd.shader_create_from_spirv((load(SHADER_PATH) as RDShaderFile).get_spirv())
	self._need_clean.append(self._shader)
	self._pipeline = self._rd.compute_pipeline_create(self._shader)
	
	return

func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if _callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var screen_tex : RID = render_scene_buffers.get_texture("render_buffers", "color")
	var screen_tex_format : RDTextureFormat = self._rd.texture_get_format(screen_tex)
	var screen_size : Vector2i = Vector2i(screen_tex_format.width, screen_tex_format.height)
	
	self._prepare_resources(screen_size)
	
	# set 0
	var int_param_uniform : RDUniform = RDUniform.new()
	int_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_param_uniform.binding = 0
	int_param_uniform.add_id(self._int_params)
	
	var float_param_uniform : RDUniform = RDUniform.new()
	float_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	float_param_uniform.binding = 1
	float_param_uniform.add_id(self._float_params)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._shader, 0, [int_param_uniform, float_param_uniform])
	
	# set 1
	var tex_uniform :RDUniform = RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(screen_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._shader, 1, [tex_uniform])
	
	@warning_ignore("integer_division")
	var x_groups : int = (screen_size.x - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (screen_size.y - 1) / GROUP_SIZE.y + 1
	var z_groups : int = 1
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	
	return

func _prepare_resources(size : Vector2i) -> void:
	# int params
	var int_array : PackedInt32Array = [size.x, size.y, 0, 0]
	var int_byte : PackedByteArray = int_array.to_byte_array()
	if not self._int_params.is_valid():
		self._int_params = self._rd.storage_buffer_create(int_byte.size())
		self._need_clean.append(self._int_params)
	self._rd.buffer_update(self._int_params, 0, int_byte.size(), int_byte)
	
	# float params
	var float_array : PackedFloat32Array = []
	float_array.append_array([self.inside_color.r, self.inside_color.g, self.inside_color.b])
	float_array.append(self.radius)
	float_array.append_array([self.outside_color.r, self.outside_color.g, self.outside_color.b])
	float_array.append(repeat)
	var float_byte : PackedByteArray = float_array.to_byte_array()
	if not self._float_params.is_valid():
		self._float_params = self._rd.storage_buffer_create(float_byte.size())
		self._need_clean.append(self._float_params)
	self._rd.buffer_update(self._float_params, 0, float_byte.size(), float_byte)
	
	return
