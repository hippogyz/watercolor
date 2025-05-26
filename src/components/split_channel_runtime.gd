class_name SplitChannelRuntime extends RefCounted

var split_channel : SplitChannel

var _rd : RenderingDevice
var _need_clean : Array[RID] = []
const GROUP_SIZE : Vector3i = Vector3i(8, 8, 1)

const SPLIT_SHADER : String = "res://shaders/split_channel.glsl"
var _split_shader : RID
var _split_pipeline : RID
var _split_output_tex : RID
var _split_int_params : RID

const MIX_SHADER : String = "res://shaders/mix_channel.glsl"
var _mix_shader : RID
var _mix_pipeline : RID
var _mix_int_params : RID
var _mix_source_sampler : RID
var _mix_curve_tex : RID
var _mix_curve_sampler : RID

func _init() -> void:
	self._rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(self._init_runtime)
	return

func _notification(what: int) -> void:
	# 'self' reference is missing during PREDELETE notification
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
	
	self._split_shader = self._rd.shader_create_from_spirv((load(SPLIT_SHADER) as RDShaderFile).get_spirv())
	self._need_clean.append(self._split_shader)
	self._split_pipeline = self._rd.compute_pipeline_create(_split_shader)
	
	self._mix_shader = self._rd.shader_create_from_spirv((load(MIX_SHADER) as RDShaderFile).get_spirv())
	self._need_clean.append(self._mix_shader)
	self._mix_pipeline = self._rd.compute_pipeline_create(_mix_shader)
	
	var sampler_state = RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.unnormalized_uvw = false
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	self._mix_source_sampler = self._rd.sampler_create(sampler_state)
	self._need_clean.append(self._mix_source_sampler)
	
	return

func split(source_tex : RID) -> RID:
	var source_format : RDTextureFormat = self._rd.texture_get_format(source_tex)
	var source_size : Vector2i = Vector2i(source_format.width, source_format.height)
	self._prepare_split_output(source_size)
	self._prepare_split_int_params(source_size)
	
	# set 0
	var source_tex_uniform = RDUniform.new()
	source_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	source_tex_uniform.binding = 0
	source_tex_uniform.add_id(source_tex)
	
	var int_params_uniform = RDUniform.new()
	int_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_params_uniform.binding = 1
	int_params_uniform.add_id(self._split_int_params)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._split_shader, 0, [source_tex_uniform, int_params_uniform])
	
	# set 1
	var splitted_tex_uniform = RDUniform.new()
	splitted_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	splitted_tex_uniform.binding = 0
	splitted_tex_uniform.add_id(self._split_output_tex)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._split_shader, 1, [splitted_tex_uniform])
	
	@warning_ignore("integer_division")
	var x_groups : int = (source_size.x - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (source_size.y - 1) / GROUP_SIZE.y + 1
	var z_groups : int = 1
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._split_pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	
	return self._split_output_tex

func mix(mix_textures : RID, target_texture) -> void:
	var target_format : RDTextureFormat = self._rd.texture_get_format(target_texture)
	var target_size : Vector2i = Vector2i(target_format.width, target_format.height)
	self._prepare_mix_int_params(target_size)
	self._prepare_mix_curve()
	
	# set 0
	var mix_tex_uniform = RDUniform.new()
	mix_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	mix_tex_uniform.binding = 0
	mix_tex_uniform.add_id(self._mix_source_sampler)
	mix_tex_uniform.add_id(mix_textures)
	
	var int_params_uniform = RDUniform.new()
	int_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	int_params_uniform.binding = 1
	int_params_uniform.add_id(self._mix_int_params)
	
	var curve_uniform = RDUniform.new()
	curve_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	curve_uniform.binding = 2
	curve_uniform.add_id(self._mix_curve_sampler)
	curve_uniform.add_id(self._mix_curve_tex)
	
	var uniform_set_0 = UniformSetCacheRD.get_cache(self._mix_shader, 0, [mix_tex_uniform, int_params_uniform, curve_uniform])
	
	# set 1
	var target_tex_uniform = RDUniform.new()
	target_tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	target_tex_uniform.binding = 0
	target_tex_uniform.add_id(target_texture)
	
	var uniform_set_1 = UniformSetCacheRD.get_cache(self._mix_shader, 1, [target_tex_uniform])
	
	@warning_ignore("integer_division")
	var x_groups : int = (target_size.x - 1) / GROUP_SIZE.x + 1
	@warning_ignore("integer_division")
	var y_groups : int = (target_size.y - 1) / GROUP_SIZE.y + 1
	var z_groups : int = 1
	
	var compute_list = self._rd.compute_list_begin()
	self._rd.compute_list_bind_compute_pipeline(compute_list, self._mix_pipeline)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
	self._rd.compute_list_bind_uniform_set(compute_list, uniform_set_1, 1)
	self._rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	self._rd.compute_list_end()
	return

#region split

func _prepare_split_output(source_size : Vector2i) -> void:
	var current_layer : int = 0
	var target_layer : int = 3
	var current_size : Vector2i = Vector2i.ZERO
	if self._split_output_tex.is_valid():
		var current_tex_format = self._rd.texture_get_format(self._split_output_tex)
		current_size = Vector2i(current_tex_format.width, current_tex_format.height)
		current_layer = current_tex_format.array_layers
	
	if self.split_channel == null or self.split_channel.enable == false:
		target_layer = 3
	else:
		target_layer = self.split_channel.channel_split_count * 3
	
	var size_unmatched : bool = current_size != source_size
	var layer_unmatched : bool = current_layer != target_layer
	
	# don't need recreate
	if !size_unmatched and !layer_unmatched:
		return
	
	# recreate output tex
	self._free_res(self._split_output_tex)
	
	var texture_format : RDTextureFormat = RDTextureFormat.new()
	texture_format.format = RenderingDevice.DATA_FORMAT_R16_UNORM
	texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	texture_format.width = source_size.x
	texture_format.height = source_size.y
	texture_format.array_layers = target_layer
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	texture_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	texture_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	
	self._split_output_tex = self._rd.texture_create(texture_format, RDTextureView.new())
	self._need_clean.append(self._split_output_tex)
	return

func _prepare_split_int_params(source_size : Vector2i) -> void:
	var channel_mode : int = self.split_channel.split_type if self.split_channel != null else SplitChannel.ChannelType.CMY
	
	var res_available = self.split_channel != null and self.split_channel.enable
	var split_count : int = self.split_channel.channel_split_count  if res_available else 1
	
	var array : PackedInt32Array = [source_size.x, source_size.y, channel_mode, split_count]
	var byte_array : PackedByteArray = array.to_byte_array()
	
	if not self._split_int_params.is_valid():
		self._split_int_params = self._rd.storage_buffer_create(byte_array.size())
		self._need_clean.append(self._split_int_params)
	
	self._rd.buffer_update(self._split_int_params, 0, byte_array.size(), byte_array)
	return

#endregion

#region mix

func _prepare_mix_int_params(tex_size : Vector2i) -> void:
	var channel_mode : int = self.split_channel.split_type if self.split_channel != null else SplitChannel.ChannelType.CMY
	
	var res_available = self.split_channel != null and self.split_channel.enable
	var split_count : int = self.split_channel.channel_split_count  if res_available else 1
	
	var view_channel : Vector3i = Vector3i.ZERO
	view_channel.x = self._read_mix_view_channel(SplitChannel.CHANNEL_1)
	view_channel.y = self._read_mix_view_channel(SplitChannel.CHANNEL_2)
	view_channel.z = self._read_mix_view_channel(SplitChannel.CHANNEL_3)
	
	var view_split_flag : int = self.split_channel.view_split_flag if self.split_channel != null else ((1 << 32) - 1)
	
	var array : PackedInt32Array = [tex_size.x, tex_size.y, channel_mode, split_count]
	array.append_array([view_channel.x, view_channel.y, view_channel.z, view_split_flag])
	var byte_array : PackedByteArray = array.to_byte_array()
	
	if not self._mix_int_params.is_valid():
		self._mix_int_params = self._rd.storage_buffer_create(byte_array.size())
		self._need_clean.append(self._mix_int_params)
	
	self._rd.buffer_update(self._mix_int_params, 0, byte_array.size(), byte_array)
	return

func _read_mix_view_channel(channel_flag : int) -> int:
	if self.split_channel == null:
		return 1
	return 1 if ((self.split_channel.view_channel & channel_flag) != 0) else 0

func _prepare_mix_curve() -> void:
	var current_curve_size : int = 0
	if self._mix_curve_tex.is_valid():
		var curve_tex_format : RDTextureFormat = self._rd.texture_get_format(self._mix_curve_tex)
		current_curve_size = curve_tex_format.width
	
	var target_curve_size : int = 2
	var has_curve = self.split_channel != null and self.split_channel.mix_curve != null
	if has_curve:
		target_curve_size = self.split_channel.mix_curve_resolution
	
	# create texture
	if !self._mix_curve_tex.is_valid() or target_curve_size != current_curve_size:
		self._free_res(self._mix_curve_tex)
	
		var texture_format : RDTextureFormat = RDTextureFormat.new()
		texture_format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
		texture_format.texture_type = RenderingDevice.TEXTURE_TYPE_1D
		texture_format.width = target_curve_size
		texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		texture_format.usage_bits |= RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		
		self._mix_curve_tex = self._rd.texture_create(texture_format, RDTextureView.new())
		self._need_clean.append(_mix_curve_tex)
	
	# create sampler
	if !self._mix_curve_sampler.is_valid():
		var sampler_state : RDSamplerState = RDSamplerState.new()
		sampler_state.unnormalized_uvw = false
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		self._mix_curve_sampler = self._rd.sampler_create(sampler_state)
		self._need_clean.append(self._mix_curve_sampler)
	
	# update curve data  TODO: don't update each frame?
	var curve_data : PackedFloat32Array = []
	if has_curve:
		for x in target_curve_size:
			var val = self.split_channel.mix_curve.sample(float(x) / (target_curve_size - 1))
			curve_data.append(clamp(val, 0.0, 1.0))
	else:
		curve_data.append(0.0)
		curve_data.append(1.0)
	var byte_array = curve_data.to_byte_array()
	self._rd.texture_update(self._mix_curve_tex, 0, byte_array)
	
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
