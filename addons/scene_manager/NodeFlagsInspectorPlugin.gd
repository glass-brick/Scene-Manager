extends EditorInspectorPlugin

var SingletonCheckProperty = load('res://addons/scene_manager/SingletonCheckProperty.gd')
var SingletonNameProperty = load('res://addons/scene_manager/SingletonNameProperty.gd')


func can_handle(object: Object):
	return object is Node


func parse_begin(object: Object):
	add_property_editor("singleton_check", SingletonCheckProperty.new())
	add_property_editor("singleton_name", SingletonNameProperty.new())
