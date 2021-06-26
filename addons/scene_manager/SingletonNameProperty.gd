extends EditorProperty

var line_edit = LineEdit.new()
var edited_control = null
var meta_name = SceneManagerPlugin.get_singleton_meta_name()


func _ready():
	label = "Entity name"

	line_edit.connect("text_changed", self, "_on_text_changed")
	add_child(line_edit)


func _physics_process(_delta):
	if not edited_control and get_edited_object():
		edited_control = get_edited_object()
		if edited_control.has_meta(meta_name):
			line_edit.text = edited_control.get_meta(meta_name)
	if edited_control:
		draw_red = (
			edited_control.has_meta(meta_name)
			and edited_control.get_meta(meta_name) == ""
			and edited_control.is_in_group(meta_name)
		)


func _on_text_changed(new_text: String):
	edited_control.set_meta(meta_name, new_text)
