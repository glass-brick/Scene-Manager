extends Node

# Lives under the tree root, not inside current_scene, so it survives the swaps it drives.

func _ready() -> void:
	await get_tree().process_frame
	var failures := []

	await SceneManager.change_scene("res://demo/test2.tscn", {"speed": 20, "wait_time": 0.0})
	_expect(failures, "Level2", "plain change_scene")

	SceneManager.preload_scene("res://demo/test.tscn")
	await SceneManager.background_load_finished
	if not SceneManager.is_scene_ready("res://demo/test.tscn"):
		failures.append("preload_scene did not mark the scene ready")

	await SceneManager.change_scene("res://demo/test.tscn", {
		"speed": 20, "wait_time": 0.0, "background_loading": true, "pattern": "squares",
	})
	_expect(failures, "Level1", "background change_scene")

	await SceneManager.change_scene("res://demo/test2.tscn", {
		"speed": 20, "wait_time": 0.0, "skip_fade_out": true,
	})
	_expect(failures, "Level2", "skip_fade_out change_scene")

	await SceneManager.reload_scene({"speed": 20, "wait_time": 0.0})
	_expect(failures, "Level2", "reload_scene")

	if failures.is_empty():
		print("INTEGRATION_OK")
	else:
		for failure in failures:
			print("INTEGRATION_FAIL: ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _expect(failures: Array, scene_name: String, what: String) -> void:
	var current = get_tree().current_scene
	if current == null:
		failures.append("%s left no current scene" % what)
	elif current.name != scene_name:
		failures.append("%s installed %s, expected %s" % [what, current.name, scene_name])
