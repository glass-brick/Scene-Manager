tool
extends EditorPlugin


func _enter_tree():
	add_autoload_singleton("SceneManager", "res://addons/scene_manager/SceneManager.tscn")


func _exit_tree():
	remove_autoload_singleton("SceneManager")
