extends Node

export var test_scene: PackedScene

func _ready():
	yield(SceneManager, "scene_loaded")
	SceneManager.get_entity("Button").connect("button_down", self, "_on_Button_button_down")


func _on_Button_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			test_scene,
			{"pattern_enter": "diagonal", "pattern_leave": "curtains", "invert_on_leave": false}
		)
