extends "res://addons/scene_manager/SceneTreeAdapter.gd"

var sandbox: Node
var current_scene
var freed_scenes := []
var added_scenes := []
var set_current_scene_calls := []
var reload_count := 0


func _init(tree: SceneTree, sandbox_node: Node) -> void:
	super(tree)
	sandbox = sandbox_node


func get_current_scene() -> Node:
	return current_scene if is_instance_valid(current_scene) else null


func set_current_scene(scene: Node) -> void:
	current_scene = scene
	set_current_scene_calls.append(scene)


func reload_current_scene() -> void:
	reload_count += 1


func add_scene(scene: Node) -> void:
	added_scenes.append(scene)
	sandbox.add_child(scene)


func free_scene(scene: Node) -> void:
	freed_scenes.append(scene)
	scene.queue_free()
