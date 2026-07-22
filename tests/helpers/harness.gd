extends RefCounted

const SM_SCENE = preload("res://addons/scene_manager/SceneManager.tscn")
const SpyTreeAdapter = preload("res://tests/helpers/spy_tree_adapter.gd")

const FAST_OPTIONS := { "speed": 50, "wait_time": 0.0 }

var manager: Node
var sandbox: Node
var adapter
var initial_scene: Node


func _init(test, tree: SceneTree) -> void:
	sandbox = Node.new()
	test.add_child_autofree(sandbox)

	initial_scene = Node.new()
	initial_scene.name = "InitialScene"
	sandbox.add_child(initial_scene)

	manager = SM_SCENE.instantiate()
	adapter = SpyTreeAdapter.new(tree, sandbox)
	adapter.current_scene = initial_scene
	manager._adapter = adapter
	test.add_child_autofree(manager)


func options(extra: Dictionary = { }) -> Dictionary:
	var merged := FAST_OPTIONS.duplicate()
	for key in extra:
		merged[key] = extra[key]
	return merged


func shader_param(name: String):
	return manager._shader_blend_rect.material.get_shader_parameter(name)
