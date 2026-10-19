@tool
extends RichTextEffect
class_name RichTextMisgender

var bbcode = "misgender"

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	return true
