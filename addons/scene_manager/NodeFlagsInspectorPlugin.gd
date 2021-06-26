extends EditorInspectorPlugin

var control = preload('NodeFlagsInspector.tscn')


func can_handle(object: Object):
	return object is Node


func parse_begin(object: Object):
	add_custom_control(control.instance())
