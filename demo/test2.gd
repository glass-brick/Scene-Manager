extends Node

var internal_variable = 13

func _ready():
	await SceneManager.scene_loaded
	SceneManager.get_entity("Button").button_down.connect(_on_button_down)

func _on_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			"res://demo/test.tscn", {
				"pattern_enter": "diagonal",
				"pattern_leave": "curtains",
				"invert_on_leave": false,
				"on_tree_enter": func(scene): scene.internal_variable += internal_variable
			}
		)
