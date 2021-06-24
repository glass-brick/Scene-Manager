extends Node2D

signal scene_unloaded
signal scene_loaded
signal transition_finished

var is_transitioning := false
onready var _tree := get_tree()
onready var _root := _tree.get_root()
onready var _current_scene := _tree.current_scene
onready var _animation_player := $AnimationPlayer
onready var _fade_rect := $CanvasLayer/Fade
onready var _shader_blend_rect := $CanvasLayer/ShaderFade

enum FadeTypes { Fade, ShaderFade }

var default_options = {
	"type": FadeTypes.Fade,
	"speed": 2,
	"color": Color("#000000"),
	"shader_pattern": "squares",
	"wait_time": 0.5,
	"invert_on_leave": true,
	"ease": false
}
# extra_options = {
#   "shader_pattern_enter": DEFAULT_IMAGE,
#   "shader_pattern_leave": DEFAULT_IMAGE,
#   "ease_enter": true,
#   "ease_leave": true,
# }


func _load_pattern(pattern):
	if pattern is String:
		if pattern.is_abs_path():
			return load(pattern)
		return load("res://addons/scene_manager/shader_patterns/%s.png" % pattern)
	elif not pattern is Texture:
		push_error("shader_pattern %s is not a valid Texture or path" % pattern)
	return pattern


func _get_final_options(initial_options: Dictionary):
	var options = initial_options.duplicate()
	for key in default_options.keys():
		if not options.has(key):
			options[key] = default_options[key]

	for pattern_key in ["shader_pattern", "shader_pattern_enter", "shader_pattern_leave"]:
		if pattern_key in options:
			options[pattern_key] = _load_pattern(options[pattern_key])

	return options


func change_scene(path, setted_options: Dictionary = {}):
	var options = _get_final_options(setted_options)
	yield(_fade_out(options), "completed")
	_replace_scene(path)
	yield(_tree.create_timer(options["wait_time"]), "timeout")
	yield(_fade_in(options), "completed")


func _replace_scene(path):
	if path == null:
		# if no path, assume we want a reload
		_tree.reload_current_scene()
		emit_signal("scene_loaded")
		return
	_current_scene.free()
	emit_signal("scene_unloaded")
	var following_scene = ResourceLoader.load(path)
	_current_scene = following_scene.instance()
	_root.add_child(_current_scene)
	_tree.set_current_scene(_current_scene)
	emit_signal("scene_loaded")


func reload_scene(setted_options: Dictionary = {}):
	yield(change_scene(null, setted_options), "completed")


func _fade_out(options):
	is_transitioning = true
	_animation_player.playback_speed = options["speed"]

	match options["type"]:
		FadeTypes.Fade:
			_fade_rect.color = options["color"]
			_animation_player.play("ColorFade")

		FadeTypes.ShaderFade:
			var pattern = options.get("shader_pattern_enter", options["shader_pattern"])
			var ease_transition = options.get("ease_enter", options["ease"])

			_shader_blend_rect.material.set_shader_param("dissolve_texture", pattern)
			_shader_blend_rect.material.set_shader_param("fade_color", options["color"])
			_shader_blend_rect.material.set_shader_param("inverted", false)
			_animation_player.play("ShaderFadeEase" if ease_transition else "ShaderFade")

	yield(_animation_player, "animation_finished")


func _fade_in(options):
	match options["type"]:
		FadeTypes.Fade:
			_animation_player.play_backwards("ColorFade")

		FadeTypes.ShaderFade:
			var pattern = options.get("shader_pattern_leave", options["shader_pattern"])
			var ease_transition = options.get("ease_leave", options["ease"])

			_shader_blend_rect.material.set_shader_param("dissolve_texture", pattern)
			_shader_blend_rect.material.set_shader_param("inverted", options["invert_on_leave"])
			_animation_player.play_backwards("ShaderFadeEase" if ease_transition else "ShaderFade")

	yield(_animation_player, "animation_finished")
	is_transitioning = false
	emit_signal("transition_finished")
