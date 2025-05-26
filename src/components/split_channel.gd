@tool
class_name SplitChannel extends Resource

@export var enable : bool = true

enum ChannelType { CMY = 0, RGB = 1, }
@export var split_type : ChannelType = ChannelType.CMY
@export_range(2, 8, 1) var channel_split_count : int = 4

const CHANNEL_1 : int = 1
const CHANNEL_2 : int = 2
const CHANNEL_3 : int = 4
const ALL_CHANNEL : int = CHANNEL_1 | CHANNEL_2 | CHANNEL_3
@export_flags("Channel1", "Channel2", "Channel3") var view_channel : int = ALL_CHANNEL
@export_flags_3d_render var view_split_flag = (1 << 32) - 1
@export var mix_curve : Curve
@export_range(8, 128, 1) var mix_curve_resolution : int = 32


func override(source : SplitChannel) -> void:
	self.enable = source.enable
	self.split_type = source.split_type
	self.channel_split_count = source.channel_split_count
	self.view_channel = source.view_channel
	self.view_split_flag = source.view_split_flag
	self.mix_curve = source.mix_curve
	self.mix_curve_resolution = source.mix_curve_resolution
	return
