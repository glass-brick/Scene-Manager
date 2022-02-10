extends Node


func _ready():
	await SceneManager.scene_loaded

func _on_button_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			'res://demo/test2.tscn', {"pattern_enter": "scribbles", "pattern_leave": "squares"}
		)
