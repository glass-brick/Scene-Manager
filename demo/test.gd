extends Node

func ready():
	await SceneManager.scene_loaded
	SceneManager.get_entity("Button").button_down.connect("_on_button_down", self)
	print(SceneManager.get_entity("Button"))

func _on_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			"res://demo/test2.tscn", {"pattern_enter": "fade", "pattern_leave": "squares"}
		)
