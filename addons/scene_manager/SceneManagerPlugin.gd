tool
extends EditorPlugin
class_name SceneManagerPlugin

static func get_singleton_group():
	return "scene_manager_entity_nodes"
static func get_singleton_meta_name():
	return "entity_name"

var _inspector_plugin


func _enter_tree():
	add_autoload_singleton("SceneManager", "res://addons/scene_manager/SceneManager.tscn")
	_inspector_plugin = load("res://addons/scene_manager/NodeFlagsInspectorPlugin.gd").new()
	add_inspector_plugin(_inspector_plugin)


func _exit_tree():
	remove_autoload_singleton("SceneManager")
	remove_inspector_plugin(_inspector_plugin)
