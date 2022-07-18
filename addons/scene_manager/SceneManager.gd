extends Node2D

signal fade_complete
signal scene_unloaded
signal scene_loaded
signal transition_finished

var is_transitioning := false
onready var _tree := get_tree()
onready var _root := _tree.get_root()
onready var _current_scene := _tree.current_scene
onready var _animation_player := $AnimationPlayer
onready var _shader_blend_rect := $CanvasLayer/ColorRect
var _user_animation_player: AnimationPlayer

enum FadeTypes { Fade, ShaderFade }

var default_options := {
	"speed": 2,
	"color": Color("#000000"),
	"pattern": "fade",
	"wait_time": 0.5,
	"invert": false,
	"invert_on_leave": true,
	"ease": 1.0,
	"skip_scene_change": false,
	"skip_fade_out": false,
	"skip_fade_in": false,
	"animation_name": null
}
# extra_options = {
#   "pattern_enter": DEFAULT_IMAGE,
#   "pattern_leave": DEFAULT_IMAGE,
#   "ease_enter": 1.0,
#   "ease_leave": 1.0,
#   "animation_name_enter": null,
#		"animation_name_leave": null,
# }

var new_names := {
	"shader_pattern": "pattern",
	"shader_pattern_enter": "pattern_enter",
	"shader_pattern_leave": "pattern_leave",
	"no_scene_change": "skip_scene_change",
}

var singleton_entities := {}
var _previous_scene = null


func _ready() -> void:
	_set_singleton_entities()
	call_deferred("emit_signal", "scene_loaded")


func _set_singleton_entities() -> void:
	singleton_entities = {}
	var entities = _current_scene.get_tree().get_nodes_in_group(
		SceneManagerConstants.SINGLETON_GROUP_NAME
	)
	for entity in entities:
		var has_entity_name = entity.has_meta(SceneManagerConstants.SINGLETON_META_NAME)
		assert(
			has_entity_name,
			(
				"The node %s was set as a singleton entity, but no entity name was provided."
				% entity.name
			)
		)
		var entity_name = entity.get_meta(SceneManagerConstants.SINGLETON_META_NAME)
		assert(
			not singleton_entities.has(entity_name),
			(
				"The entity name %s is already being used more than once! Please check that your entity name is unique within the scene."
				% entity_name
			)
		)
		singleton_entities[entity_name] = entity


func _load_pattern(pattern) -> Texture:
	assert(
		pattern is Texture or pattern is String,
		"Pattern %s is not a valid Texture, absolute path, or built-in texture." % pattern
	)

	if pattern is String:
		if pattern.is_abs_path():
			return load(pattern) as Texture
		elif pattern == "fade":
			return null
		return load("res://addons/scene_manager/shader_patterns/%s.png" % pattern) as Texture
	return pattern


func _get_final_options(initial_options: Dictionary) -> Dictionary:
	var options = initial_options.duplicate()

	for key in options:
		if new_names.has(key):
			var new_key = new_names[key]
			options[new_key] = options[key]
		if key in ["ease", "ease_enter", "ease_leave"] and options[key] is bool:
			options[key] = 0.5 if options[key] else 1.0

	for key in default_options.keys():
		if not options.has(key):
			options[key] = default_options[key]

	for pattern_key in ["pattern_enter", "pattern_leave"]:
		options[pattern_key] = (
			_load_pattern(options[pattern_key])
			if pattern_key in options
			else _load_pattern(options["pattern"])
		)

	for ease_key in ["ease_enter", "ease_leave"]:
		if not ease_key in options:
			options[ease_key] = options["ease"]

	for animation_name_key in ["animation_name_enter", "animation_name_leave"]:
		if not animation_name_key in options:
			options[animation_name_key] = options["animation_name"]

	return options


func _process(_delta: float) -> void:
	if not is_instance_valid(_previous_scene) and _tree.current_scene:
		_previous_scene = _tree.current_scene
		_current_scene = _tree.current_scene
		_set_singleton_entities()
		emit_signal("scene_loaded")
	if _tree.current_scene != _previous_scene:
		_previous_scene = _tree.current_scene


func _reload_scene() -> void:
	_tree.reload_current_scene()
	yield(_tree.create_timer(0.0), "timeout")
	_current_scene = _tree.current_scene


func _replace_scene(scene) -> void:
	_current_scene.queue_free()
	emit_signal("scene_unloaded")
	var following_scene = _load_resource(scene)
	_current_scene = following_scene.instance()
	yield(_tree.create_timer(0.0), "timeout")
	_root.add_child(_current_scene)
	_tree.set_current_scene(_current_scene)


func _load_resource(resource) -> Resource:
	if resource is PackedScene:
		return resource
	return ResourceLoader.load(resource)


func _user_fade_out(options: Dictionary):
	assert(_user_animation_player is AnimationPlayer, "No animation player was set.")
	_user_animation_player.playback_speed = options["speed"]
	_user_animation_player.play(options["animation_name_enter"])
	yield(_user_animation_player, "animation_finished")


func _user_fade_in(options: Dictionary):
	assert(_user_animation_player is AnimationPlayer, "No animation player was set.")
	_user_animation_player.playback_speed = options["speed"]
	_user_animation_player.play_backwards(options["animation_name_leave"])
	yield(_user_animation_player, "animation_finished")


func _plugin_fade_out(options: Dictionary):
	_animation_player.playback_speed = options["speed"]
	_shader_blend_rect.material.set_shader_param("dissolve_texture", options["pattern_enter"])
	_shader_blend_rect.material.set_shader_param("fade", not options["pattern_enter"])
	_shader_blend_rect.material.set_shader_param("fade_color", options["color"])
	_shader_blend_rect.material.set_shader_param("inverted", options["invert"])
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_enter"])
	_animation_player.play("ShaderFade")
	yield(_animation_player, "animation_finished")


func _plugin_fade_in(options: Dictionary):
	_animation_player.playback_speed = options["speed"]
	_shader_blend_rect.material.set_shader_param("dissolve_texture", options["pattern_leave"])
	_shader_blend_rect.material.set_shader_param("fade", not options["pattern_leave"])
	_shader_blend_rect.material.set_shader_param(
		"inverted", not options["invert"] if options["invert_on_leave"] else options["invert"]
	)
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_leave"])
	_animation_player.play_backwards("ShaderFade")
	yield(_animation_player, "animation_finished")


#region Public API


func change_scene(scene, setted_options: Dictionary = {}) -> void:
	var options = _get_final_options(setted_options)
	if not options["skip_fade_out"]:
		yield(fade_out(setted_options), "completed")
	if not options["skip_scene_change"]:
		if scene == null:
			_reload_scene()
		else:
			_replace_scene(scene)
	yield(_tree.create_timer(options["wait_time"]), "timeout")
	if not options["skip_fade_in"]:
		yield(fade_in(setted_options), "completed")


func reload_scene(setted_options: Dictionary = {}) -> void:
	yield(change_scene(null, setted_options), "completed")


func fade_in_place(setted_options: Dictionary = {}) -> void:
	setted_options["skip_scene_change"] = true
	yield(change_scene(null, setted_options), "completed")


func fade_out(setted_options: Dictionary = {}) -> void:
	var options = _get_final_options(setted_options)
	is_transitioning = true
	if options["animation_name_enter"]:
		yield(_user_fade_out(options), "completed")
	else:
		yield(_plugin_fade_out(options), "completed")
	emit_signal("fade_complete")


func fade_in(setted_options: Dictionary = {}) -> void:
	var options = _get_final_options(setted_options)
	if options["animation_name_leave"]:
		if not options["animation_name_enter"]:
			_animation_player.play("RESET")
		yield(_user_fade_in(options), "completed")
	else:
		if options["animation_name_enter"]:
			_user_animation_player.play("RESET")
		yield(_plugin_fade_in(options), "completed")
	is_transitioning = false
	emit_signal("transition_finished")


func set_animation_player(animation_player) -> void:
	assert(
		animation_player is String or animation_player is PackedScene,
		"set_animation_player() must receive a string (path to AnimationPlayer.tscn) or a PackedScene"
	)
	var loaded_animation_player = _load_resource(animation_player).instance()
	assert(
		loaded_animation_player is AnimationPlayer,
		(
			"The scene loaded from set_animation_player() (%s) must receive an AnimationPlayer"
			% _user_animation_player
		)
	)
	if _user_animation_player is AnimationPlayer:
		_user_animation_player.queue_free()
	_user_animation_player = loaded_animation_player
	$CanvasLayer.add_child(_user_animation_player)
	_user_animation_player.play("RESET")


func get_entity(entity_name: String) -> Node:
	assert(
		singleton_entities.has(entity_name),
		"Entity %s is not set as a singleton entity. Please define it in the editor." % entity_name
	)
	return singleton_entities[entity_name]

#endregion
