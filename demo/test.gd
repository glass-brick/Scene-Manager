extends Node

const CustomAnimationPlayer = preload("res://demo/animation_player.tscn")

var internal_variable = 42


func _ready():
	SceneManager.set_animation_player(CustomAnimationPlayer)
	$CanvasLayer/ColorRect/Button.button_down.connect(_on_button_down)
	$CanvasLayer/ColorRect/CustomButton.button_down.connect(_on_custom_button_down)


func _on_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			"res://demo/test2.tscn",
			{
				"pattern_enter": "fade",
				"pattern_leave": "squares",
				"on_tree_enter": func(scene):
					scene.internal_variable += internal_variable,
				"loading_screen": true,
				"min_loading_time": 0.5,
			},
		)


func _on_custom_button_down():
	if not SceneManager.is_transitioning:
		# The custom player covers the screen, the built-in shader fade reveals the new scene.
		SceneManager.change_scene("res://demo/test2.tscn", { "animation_name": "roll" })
