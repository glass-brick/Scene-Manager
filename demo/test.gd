extends Node


func _on_Button_button_down():
	if not SceneManager.is_transitioning:
		SceneManager.change_scene(
			'res://demo/test2.tscn',
			{
				"type": SceneManager.FadeTypes.ShaderFade,
				"shader_pattern": "scribbles",
				"shader_pattern_leave": "squares"
			}
		)
