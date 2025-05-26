class_name WashRuntime extends RefCounted

var wash_res : Wash

var _rd : RenderingDevice
var _need_clean : Array[RID] = []
const GROUP_SIZE : Vector3i = Vector3i(8, 8, 1)

const SHADER : String = "res://shaders/wash.glsl"
var _shader : RID
var _pipeline : RID

var _blur_sampler : RID
var _basic_int_params : RID

var _edge_float_params : RID

func _init() -> void:
	self._rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(self._init_runtime)
	return

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _rd == null:
			return
		
		_need_clean.reverse()
		for rid in _need_clean:
			_rd.free_rid(rid)
		_need_clean.clear()
		
		_rd = null
	return

func _init_runtime() -> void:
	if self._rd == null:
		return
	
	self._shader = self._rd.shader_create_from_spirv((load(SHADER) as RDShaderFile).get_spirv())
	self._need_clean.append(_shader)
	self._pipeline = self._rd.compute_pipeline_create(self._shader)
	
	var sampler_state = RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.unnormalized_uvw = false
	self._blur_sampler = self._rd.sampler_create(sampler_state)
	self._need_clean.append(self._blur_sampler)
	
	return

func wash(blurred_tex : RID, target_tex : RID) -> void:
	var target_tex_format = self._rd.texture_get_format(target_tex)
	
	self._prepare_basic_params(Vector2i(target_tex_format.width, target_tex_format.height))
	self._prepare_edge_params()
	
	# set 0
	var blurred_tex_uniform = RDUniform.new()
	blurred_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	blurred_tex_uniform.binding = 0
	blurred_tex_uniform.add_id(self._blur_sampler)
	blurred_tex_uniform.add_id(blurred_tex)
	
	var int_param_uniform = RDUniform.new()
	int_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_param_uniform.binding = 1
	int_param_uniform.add_id(self._basic_int_params)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._shader, 0, [blurred_tex_uniform, int_param_uniform])
	
	# set 1
	var target_tex_uniform = RDUniform.new()
	target_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	target_tex_uniform.binding = 0
	target_tex_uniform.add_id(target_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._shader, 1, [target_tex_uniform])
	
	# set 2
	var edge_uniform = RDUniform.new()
	edge_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	edge_uniform.binding = 0
	edge_uniform.add_id(self._edge_float_params)
	
	var uniform_set_2 = UniformSetCacheRD.get_cache(self._shader, 2, [edge_uniform])
	
	# group size
	@warning_ignore("integer_division")
	var x_groups : int = (target_tex_format.width - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (target_tex_format.height - 1) / GROUP_SIZE.y + 1
	@warning_ignore("integer_division")
	var z_groups : int = target_tex_format.array_layers
	
	# run
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_2, 2)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	return

#region prepare

func _prepare_basic_params(target_tex_size : Vector2i) -> void:
	var int_array : PackedInt32Array = []
	int_array.append_array([target_tex_size.x, target_tex_size.y, 0, 0])
	var int_byte = int_array.to_byte_array()
	if not self._basic_int_params.is_valid():
		self._basic_int_params = self._rd.storage_buffer_create(int_byte.size())
		self._need_clean.append(self._basic_int_params)
	self._rd.buffer_update(self._basic_int_params, 0, int_byte.size(), int_byte)
	return

func _prepare_edge_params() -> void:
	var edge_array : PackedFloat32Array = []
	edge_array.append(clamp(self.wash_res.edge_min, 0.0, 1.0))
	edge_array.append(clamp(self.wash_res.edge_max, 0.0, 1.0))
	edge_array.append(self.wash_res.edge_pow)
	
	var edge_byte = edge_array.to_byte_array()
	if not self._edge_float_params.is_valid():
		self._edge_float_params = self._rd.storage_buffer_create(edge_byte.size())
		self._need_clean.append(self._edge_float_params)
	self._rd.buffer_update(self._edge_float_params, 0, edge_byte.size(), edge_byte)
	return

#endregion

#region helper

func _free_res(rid : RID) -> void:
	if rid.is_valid() == false:
		return
	
	self._need_clean.erase(rid)
	var rd : RenderingDevice = self._rd
	(func(): rd.free_rid(rid)).call_deferred()
	return

#endregion
