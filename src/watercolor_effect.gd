@tool
class_name Watercolor extends CompositorEffect

@export var _reset : bool:
	get: return false
	set(value): if value: self._init()

@export var split_channel : SplitChannel
var _split_channel_shadow : SplitChannel
var _split_channel_runtime : SplitChannelRuntime

@export var blur : Blur
var _blur_shadow : Blur
var _blur_runtime : BlurRuntime

@export var wash : Wash
var _wash_shadow : Wash
var _wash_runtime : WashRuntime

func _init() -> void:
	self.effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	
	if self.split_channel == null:
		self.split_channel = SplitChannel.new()
	self._split_channel_shadow = SplitChannel.new()
	self._split_channel_runtime = SplitChannelRuntime.new()
	self._split_channel_runtime.split_channel = self._split_channel_shadow
	
	if self.blur == null:
		self.blur = Blur.new()
	self._blur_shadow = Blur.new()
	self._blur_runtime = BlurRuntime.new()
	self._blur_runtime.blur_res = self._blur_shadow
	
	if self.wash == null:
		self.wash = Wash.new()
	self._wash_shadow = Wash.new()
	self._wash_runtime = WashRuntime.new()
	self._wash_runtime.wash_res = self._wash_shadow

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if callback_type != CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	
	# Update input
	if self.split_channel != null:
		self._split_channel_shadow.override(self.split_channel)
	
	if self.blur != null:
		self._blur_shadow.override(self.blur)
	else:
		self._blur_shadow.enable = false
		self._blur_shadow.blur_debug = false
	
	if self.wash != null:
		self._wash_shadow.override(self.wash)
	else:
		self._wash_shadow.enable = false
	
	# Run
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var source_tex : RID = render_scene_buffers.get_texture("render_buffers", "color")
	
	# split
	var splitted_textures : RID = self._split_channel_runtime.split(source_tex)
	
	# blur
	var blurred_textures : RID = RID()
	if self._blur_shadow.enable:
		if self._blur_shadow.use_double_pass:
			blurred_textures = self._blur_runtime.blur_double_pass(splitted_textures)
		else:
			blurred_textures = self._blur_runtime.blur(splitted_textures)
	
	# wash
	if self._wash_shadow.enable:
		self._wash_runtime.wash(blurred_textures, splitted_textures)
	
	# mix
	self._split_channel_runtime.mix(splitted_textures, source_tex)
	
	# blur debug
	if self._blur_shadow.enable and self._blur_shadow.blur_debug:
		self._blur_runtime.debug(blurred_textures, source_tex)
	
	return
