tool
extends EditorPlugin

var plugin


func _enter_tree():
	add_autoload_singleton("SceneManager", "res://addons/scene_manager/SceneManager.tscn")
	plugin = preload("res://addons/scene_manager/NodeFlagsInspectorPlugin.gd").new()
	add_inspector_plugin(plugin)


func _exit_tree():
	remove_autoload_singleton("SceneManager")
	remove_inspector_plugin(plugin)
