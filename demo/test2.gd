extends Node2D


func _on_Button_button_down():
	SceneManager.change_scene(
		'res://demo/test.tscn',
		{
			"type": SceneManager.FadeTypes.ShaderFade,
			"shader_pattern": "diagonal",
			"shader_pattern_leave": "curtains",
			"invert_on_leave": true
		}
	)
