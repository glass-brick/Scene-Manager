extends Control

@onready var _progress_bar : ProgressBar = $CenterContainer/ProgressBar

func set_progress(value: float) -> void:
	_progress_bar.value = value * _progress_bar.max_value
