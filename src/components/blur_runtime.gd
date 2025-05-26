class_name BlurRuntime extends RefCounted

var blur_res : Blur

var _rd : RenderingDevice
var _need_clean : Array[RID] = []
const GROUP_SIZE : Vector3i = Vector3i(8, 8, 1)

var _channel_sampler : RID

# direct
const SHADER_PATH : String = "res://shaders/blur_double_pass.glsl"
var _shader : RID
var _pipeline : RID

var _blurred_tex : RID
var _int_param : RID
var _direct_kernel_buffer : RID
var _direct_kernel_length : int = 0

# double pass
const DOUBLE_PASS_SHADER_PATH : String = "res://shaders/blur_double_pass.glsl"
var _dp_shader : RID
var _dp_pipeline : RID

var _dp_blurred_mid_tex : RID
var _dp_blurred_tex : RID
var _dp_int_param : RID
var _kernel_mid_buffer : RID
var _kernel_buffer : RID
var _kernel_buffer_length : int = 0

# debug
const DEBUG_SHADER_PATH : String = "res://shaders/blur_debug.glsl"
var _debug_shader : RID
var _debug_pipeline : RID

var _debug_int_param : RID

func _init() -> void:
	self._rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(self._init_runtime)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _rd == null:
			return
		
		_need_clean.reverse()
		for rid : RID in _need_clean:
			_rd.free_rid(rid)
		_need_clean.clear()
		
		_rd = null
	return

func _init_runtime() -> void:
	if self._rd == null:
		return
	
	# sampler
	var sampler_state = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.unnormalized_uvw = false
	self._channel_sampler = self._rd.sampler_create(sampler_state)
	self._need_clean.append(self._channel_sampler)
	
	# direct
	self._shader = self._rd.shader_create_from_spirv((load(SHADER_PATH) as RDShaderFile).get_spirv())
	self._need_clean.append(self._shader)
	self._pipeline = self._rd.compute_pipeline_create(self._shader)
	
	# double pass
	self._dp_shader = self._rd.shader_create_from_spirv((load(DOUBLE_PASS_SHADER_PATH) as RDShaderFile).get_spirv())
	self._need_clean.append(self._dp_shader)
	self._dp_pipeline = self._rd.compute_pipeline_create(self._dp_shader)
	
	# debug
	self._debug_shader = self._rd.shader_create_from_spirv((load(DEBUG_SHADER_PATH) as RDShaderFile).get_spirv())
	self._need_clean.append(self._debug_shader)
	self._debug_pipeline = self._rd.compute_pipeline_create(self._debug_shader)
	
	return

func blur(channel_tex : RID) -> RID:
	var channel_tex_format = self._rd.texture_get_format(channel_tex)
	var channel_tex_size = Vector2i(channel_tex_format.width, channel_tex_format.height)
	var split_count : int = channel_tex_format.array_layers / 3
	self._prepare_tex(channel_tex_size, split_count)
	self._prepare_params()
	
	# set 0
	var source_uniform = RDUniform.new()
	source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	source_uniform.binding = 0
	source_uniform.add_id(self._channel_sampler)
	source_uniform.add_id(channel_tex)
	
	var int_uniform = RDUniform.new()
	int_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_uniform.binding = 1
	int_uniform.add_id(self._int_param)
	
	var float_uniform = RDUniform.new()
	float_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	float_uniform.binding = 2
	float_uniform.add_id(self._direct_kernel_buffer)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._shader, 0, [source_uniform, int_uniform, float_uniform])
	
	# set 1
	var blur_tex_uniform = RDUniform.new()
	blur_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	blur_tex_uniform.binding = 0
	blur_tex_uniform.add_id(self._blurred_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._shader, 1, [blur_tex_uniform])
	
	var blurred_tex_format = self._rd.texture_get_format(self._blurred_tex)
	@warning_ignore("integer_division")
	var x_groups : int = (blurred_tex_format.width - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (blurred_tex_format.height - 1) / GROUP_SIZE.y + 1
	@warning_ignore("integer_division")
	var z_groups : int = blurred_tex_format.array_layers
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	
	return self._blurred_tex

func blur_double_pass(channel_tex : RID) -> RID:
	var source_tex_format = self._rd.texture_get_format(channel_tex)
	var source_size = Vector2i(source_tex_format.width, source_tex_format.height)
	var source_split : int = source_tex_format.array_layers / 3
	
	self._prepare_double_pass_tex(source_size, source_split)
	self._prepare_double_pass_params()
	
	self._single_pass_blur(true, channel_tex)
	self._single_pass_blur(false, self._dp_blurred_mid_tex)
	
	return self._dp_blurred_tex

func debug(blurred_tex : RID, target_tex : RID) -> void:
	var target_tex_format = self._rd.texture_get_format(target_tex)
	var screen_size : Vector2i = Vector2i(target_tex_format.width, target_tex_format.height)
	self._prepare_debug_params(screen_size)
	
	# set 0
	var blurred_tex_uniform = RDUniform.new()
	blurred_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	blurred_tex_uniform.binding = 0
	blurred_tex_uniform.add_id(self._channel_sampler)
	blurred_tex_uniform.add_id(blurred_tex)
	
	var int_param_uniform = RDUniform.new()
	int_param_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_param_uniform.binding = 1
	int_param_uniform.add_id(self._debug_int_param)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._debug_shader, 0, [blurred_tex_uniform, int_param_uniform])
	
	# set 1
	var target_uniform = RDUniform.new()
	target_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	target_uniform.binding = 0
	target_uniform.add_id(target_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._debug_shader, 1, [target_uniform])
	
	@warning_ignore("integer_division")
	var x_groups : int = (screen_size.x - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (screen_size.y - 1) / GROUP_SIZE.y + 1
	var z_groups : int = 1
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._debug_pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	
	return

#region direct

func _prepare_tex(source_tex_size : Vector2i, target_split : int) -> void:
	var current_split : int = 0
	var current_size : Vector2i = Vector2i.ZERO
	if self._blurred_tex.is_valid():
		var tex_format = self._rd.texture_get_format(self._blurred_tex)
		current_split = tex_format.array_layers / 3
		current_size = Vector2i(tex_format.width, tex_format.height)
	
	var down_sample_level : int = max(self.blur_res.down_sample_level, 0)
	var target_size : Vector2i = source_tex_size / (1 << down_sample_level)
	if target_split != current_split or target_size != current_size:
		self._free_res(self._blurred_tex)
		
		var format = RDTextureFormat.new()
		format.format = RenderingDevice.DATA_FORMAT_R16_UNORM
		format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
		format.width = target_size.x
		format.height = target_size.y
		format.array_layers = target_split * 3
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		format.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		
		self._blurred_tex = self._rd.texture_create(format, RDTextureView.new())
		self._need_clean.append(self._blurred_tex)
	
	return

func _prepare_params() -> void:
	var target_tex_format = self._rd.texture_get_format(self._blurred_tex)
	
	# int params
	var int_array : PackedInt32Array = []
	int_array.append_array([target_tex_format.width, target_tex_format.height])
	int_array.append(self.blur_res.radial_quality * self.blur_res.polar_quality + 1)
	int_array.append(0)
	var int_byte_array : PackedByteArray = int_array.to_byte_array()
	if not self._int_param.is_valid():
		self._int_param = self._rd.storage_buffer_create(int_byte_array.size())
		self._need_clean.append(self._int_param)
	self._rd.buffer_update(self._int_param, 0, int_byte_array.size(), int_byte_array)
	
	# sample kernel
	var kernel_array : PackedVector4Array = []
	
	var origin_weight = self.blur_res.direct_weight_curve.sample(0.0) if self.blur_res.direct_weight_curve != null else 1.0
	kernel_array.append(Vector4(0, 0, origin_weight, 0))
	
	var polar_offset = 0.0
	for radial_idx : int in range(self.blur_res.radial_quality):
		var dist = float(radial_idx + 1) / self.blur_res.radial_quality
		var duv = dist * self.blur_res.radius
		var weight = 1.0
		if self.blur_res.direct_weight_curve != null:
			weight = self.blur_res.direct_weight_curve.sample(dist)
		polar_offset += self.blur_res.polar_shift
		
		for polar_idx : int in range(self.blur_res.polar_quality):
			var angle = polar_offset + TAU * float(polar_idx) / self.blur_res.polar_quality
			var vec = Vector4.ZERO
			vec.x = duv * cos(angle) * float(target_tex_format.height) / target_tex_format.width
			vec.y = duv * sin(angle)
			vec.z = weight
			kernel_array.append(vec)
	
	var kernel_byte = kernel_array.to_byte_array()
	
	var target_kernel_size = self.blur_res.radial_quality * self.blur_res.polar_quality + 1
	if self._direct_kernel_length != target_kernel_size:
		self._direct_kernel_length = target_kernel_size
		
		self._free_res(self._direct_kernel_buffer)
		
		self._direct_kernel_buffer = self._rd.storage_buffer_create(kernel_byte.size())
		self._need_clean.append(self._direct_kernel_buffer)
	
	self._rd.buffer_update(self._direct_kernel_buffer, 0, kernel_byte.size(), kernel_byte)
	
	return

#endregion

#region double pass

func _prepare_double_pass_tex(source_tex_size : Vector2i, target_split : int) -> void:
	var down_sample_level : int = max(self.blur_res.down_sample_level, 0)
	var target_tex_size : Vector2i = source_tex_size / (1 << down_sample_level)
	var current_tex_size = Vector2i.ZERO
	var current_split = 0
	if self._dp_blurred_mid_tex.is_valid():
		var tex_format = self._rd.texture_get_format(self._dp_blurred_mid_tex)
		current_tex_size = Vector2i(tex_format.width, tex_format.height)
		current_split = tex_format.array_layers / 3
	
	if target_tex_size != current_tex_size or target_split != current_split:
		self._free_res(self._dp_blurred_mid_tex)
		self._free_res(self._dp_blurred_tex)
		
		var format = RDTextureFormat.new()
		format.format = RenderingDevice.DATA_FORMAT_R16_UNORM
		format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
		format.width = target_tex_size.x
		format.height = target_tex_size.y
		format.array_layers = target_split * 3
		format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		format.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		
		self._dp_blurred_mid_tex = self._rd.texture_create(format, RDTextureView.new())
		self._need_clean.append(self._dp_blurred_mid_tex)
		
		self._dp_blurred_tex = self._rd.texture_create(format, RDTextureView.new())
		self._need_clean.append(self._dp_blurred_tex)
	
	return

func _prepare_double_pass_params() -> void:
	var tex_format = self._rd.texture_get_format(self._dp_blurred_mid_tex)
	# int params
	var int_array : PackedInt32Array = [tex_format.width, tex_format.height, self.blur_res.kernel_size * 2 + 1, 0]
	var int_byte_array = int_array.to_byte_array()
	if not self._dp_int_param.is_valid():
		self._dp_int_param = self._rd.storage_buffer_create(int_byte_array.size())
		self._need_clean.append(self._dp_int_param)
	self._rd.buffer_update(self._dp_int_param, 0, int_byte_array.size(), int_byte_array)
	
	# kernel buffer
	var kernel_mid_array : PackedVector4Array = []
	var kernel_array : PackedVector4Array = []
	var kernel_size : int = abs(self.blur_res.kernel_size)
	for i in range(-kernel_size, kernel_size + 1):
			var dist : float = float(i) / max(kernel_size, 1)
			var duv = dist * self.blur_res.kernel_scale
			var weight : float = 1.0
			if self.blur_res.kernel_weight_curve != null:
				weight = self.blur_res.kernel_weight_curve.sample(abs(dist))
			
			var mid_vec : Vector4 = Vector4(0, 0, weight, 0)
			var vec : Vector4 = Vector4(0, 0, weight, 0)
			
			if self.blur_res.horizontal_first:
				mid_vec.x = duv * float(tex_format.height) / tex_format.width
				vec.y = duv
			else:
				mid_vec.y = duv
				vec.x = duv * float(tex_format.height) / tex_format.width
			
			kernel_mid_array.append(mid_vec)
			kernel_array.append(vec)
	
	var kernel_mid_byte = kernel_mid_array.to_byte_array()
	var kernel_byte = kernel_array.to_byte_array()
	
	if self._kernel_buffer_length != self.blur_res.kernel_size:
		self._kernel_buffer_length = self.blur_res.kernel_size
		
		self._free_res(self._kernel_buffer)
		self._free_res(self._kernel_mid_buffer)
		
		self._kernel_mid_buffer = self._rd.storage_buffer_create(kernel_byte.size())
		self._need_clean.append(self._kernel_mid_buffer)
		self._kernel_buffer = self._rd.storage_buffer_create(kernel_byte.size())
		self._need_clean.append(self._kernel_buffer)
	
	self._rd.buffer_update(self._kernel_mid_buffer, 0, kernel_mid_byte.size(), kernel_mid_byte)
	self._rd.buffer_update(self._kernel_buffer, 0, kernel_byte.size(), kernel_byte)
	
	return

func _single_pass_blur(first_pass : bool, source_tex : RID) -> void:
	var int_params : RID = self._dp_int_param
	var kernel_buffer : RID = self._kernel_mid_buffer if first_pass else self._kernel_buffer
	var target_tex : RID = self._dp_blurred_mid_tex if first_pass else self._dp_blurred_tex
	
		# set 0
	var source_uniform = RDUniform.new()
	source_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	source_uniform.binding = 0
	source_uniform.add_id(self._channel_sampler)
	source_uniform.add_id(source_tex)
	
	var int_uniform = RDUniform.new()
	int_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_uniform.binding = 1
	int_uniform.add_id(int_params)
	
	var float_uniform = RDUniform.new()
	float_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	float_uniform.binding = 2
	float_uniform.add_id(kernel_buffer)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._dp_shader, 0, [source_uniform, int_uniform, float_uniform])
	
	# set 1
	var blur_tex_uniform = RDUniform.new()
	blur_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	blur_tex_uniform.binding = 0
	blur_tex_uniform.add_id(target_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._dp_shader, 1, [blur_tex_uniform])
	
	var target_tex_format = self._rd.texture_get_format(target_tex)
	@warning_ignore("integer_division")
	var x_groups : int = (target_tex_format.width - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (target_tex_format.height - 1) / GROUP_SIZE.y + 1
	@warning_ignore("integer_division")
	var z_groups : int = target_tex_format.array_layers
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._dp_pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	
	return

#endregion

#region debug

func _prepare_debug_params(screen_size : Vector2i) -> void:
	var int_array : PackedInt32Array = [screen_size.x, screen_size.y, self.blur_res.blur_debug_layer, 0];
	var int_byte_array : PackedByteArray = int_array.to_byte_array()
	if not self._debug_int_param.is_valid():
		self._debug_int_param = self._rd.storage_buffer_create(int_byte_array.size())
		self._need_clean.append(self._debug_int_param)
	self._rd.buffer_update(self._debug_int_param, 0, int_byte_array.size(), int_byte_array)
	return

#endregion

func _free_res(rid : RID) -> void:
	if rid.is_valid() == false:
		return
	
	self._need_clean.erase(rid)
	var rd : RenderingDevice = self._rd
	(func(): rd.free_rid(rid)).call_deferred()
	return
