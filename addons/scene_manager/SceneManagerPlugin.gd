@tool
extends EditorPlugin

const SceneManagerSettings = preload("res://addons/scene_manager/SceneManagerSettings.gd")


func _enter_tree():
	SceneManagerSettings.register()
	add_autoload_singleton("SceneManager", "res://addons/scene_manager/SceneManager.tscn")


func _exit_tree():
	# The settings stay declared: removing them would throw away the project's configuration
	# every time the plugin is toggled off.
	remove_autoload_singleton("SceneManager")
