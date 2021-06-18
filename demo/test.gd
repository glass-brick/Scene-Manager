extends Node2D


func _on_Button_button_down():
	SceneManager.change_scene(
		'res://demo/test2.tscn',
		{
			"type": SceneManager.FadeTypes.ShaderFade,
			"shader_pattern": "scribbles",
			"shader_pattern_leave": "squares"
		}
	)
