extends Control
## The loading screen shown when [code]loading_screen[/code] is [code]true[/code].
##
## A progress bar centred on a transparent background. To use your own instead, pass a
## [PackedScene] as [code]loading_screen[/code]; the only thing SceneManager asks of it is a
## [method set_progress] method, which is called every frame while the scene loads. Anything
## without one is still shown, just never told how far along the load is.

@onready var _progress_bar: ProgressBar = $CenterContainer/ProgressBar


## Called every frame with the load progress, from 0.0 to 1.0.
func set_progress(value: float) -> void:
	_progress_bar.value = value * _progress_bar.max_value
