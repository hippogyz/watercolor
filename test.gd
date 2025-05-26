@tool

extends Node

@export var texture : Texture

@export_tool_button("Print Format") var print_format = _print_format

var old_rid : RID

func _print_format() -> void:
	if self.texture == null:
		return
	
	var rd = RenderingServer.get_rendering_device()
	var tex = RenderingServer.texture_get_rd_texture(texture.get_rid())
	var format = rd.texture_get_format(tex)
	print(format.usage_bits as RenderingDevice.TextureUsageBits)
	print(format.width)
	print(format.height)
	print(format.texture_type)
	print(format.format)
	print(tex)
	
	if old_rid.is_valid():
		print(rd.texture_is_valid(old_rid))
		print(old_rid)
	old_rid = tex
	
	return
