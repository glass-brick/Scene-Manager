extends RefCounted

var _tree: SceneTree


func _init(tree: SceneTree = null) -> void:
	_tree = tree


func get_current_scene() -> Node:
	var scene = _tree.current_scene
	return scene if is_instance_valid(scene) else null


func set_current_scene(scene: Node) -> void:
	_tree.set_current_scene(scene)


func reload_current_scene() -> void:
	_tree.reload_current_scene()


func add_scene(scene: Node) -> void:
	_tree.get_root().add_child(scene)


func free_scene(scene: Node) -> void:
	scene.queue_free()


func create_timer(seconds: float) -> SceneTreeTimer:
	return _tree.create_timer(seconds)
