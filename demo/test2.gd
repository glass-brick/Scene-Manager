extends Node

func ready():
	await SceneManager.scene_loaded
	SceneManager.get_entity("Button").button_down.connect("_on_button_down", self)
	print(SceneManager.get_entity("Button"))

func _on_button_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			"res://demo/test.tscn",
			{"pattern_enter": "diagonal", "pattern_leave": "curtains", "invert_on_leave": false}
		)
