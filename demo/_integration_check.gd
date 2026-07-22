extends Node

const Driver = preload("res://demo/_integration_driver.gd")

func _ready() -> void:
	var driver := Node.new()
	driver.set_script(Driver)
	get_tree().root.call_deferred("add_child", driver)
