extends Node
const animation_player = preload('res://demo/animation_player.tscn')


func _ready():
	SceneManager.set_animation_player(animation_player)
	yield(SceneManager, "scene_loaded")
	SceneManager.get_entity("Button").connect("button_down", self, "_on_Button_button_down")
	SceneManager.get_entity("CustomButton").connect(
		"button_down", self, "_on_CustomButton_button_down"
	)


func _on_Button_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			'res://demo/test2.tscn', {"pattern_enter": "fade", "pattern_leave": "squares"}
		)


func _on_CustomButton_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			'res://demo/test2.tscn', {"animation_name_enter": "roll", "pattern_leave": "squares"}
		)
