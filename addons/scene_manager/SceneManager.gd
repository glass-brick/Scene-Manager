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
onready var _fade_rect := $CanvasLayer/Fade
onready var _shader_blend_rect := $CanvasLayer/ShaderFade

enum FadeTypes { Fade, ShaderFade }

var default_options = {
	"type": FadeTypes.Fade,
	"speed": 2,
	"color": Color("#000000"),
	"pattern": "squares",
	"wait_time": 0.5,
	"invert_on_leave": true,
	"ease": 1.0,
	"no_scene_change": false,
}
# extra_options = {
#   "pattern_enter": DEFAULT_IMAGE,
#   "pattern_leave": DEFAULT_IMAGE,
#   "ease_enter": true,
#   "ease_leave": true,
# }

var new_names = {
	"shader_pattern": "pattern",
	"shader_pattern_enter": "pattern_enter",
	"shader_pattern_leave": "pattern_leave"
}

var shader_exclusive_keys = [
	"pattern",
	"pattern_enter",
	"pattern_leave",
	"invert_on_leave",
	"ease",
	"ease_enter",
	"ease_leave",
]

var singleton_entities = {}


func _ready():
	_set_singleton_entities()
	call_deferred("emit_signal", "scene_loaded")


func _set_singleton_entities():
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


func get_entity(entity_name: String):
	assert(
		singleton_entities.has(entity_name),
		"Entity %s is not set as a singleton entity. Please define it in the editor." % entity_name
	)
	return singleton_entities[entity_name]


func _load_pattern(pattern):
	assert(
		pattern is Texture or pattern is String,
		"Pattern %s is not a valid Texture, absolute path, or built-in texture." % pattern
	)

	if pattern is String:
		if pattern.is_abs_path():
			return load(pattern)
		return load("res://addons/scene_manager/shader_patterns/%s.png" % pattern)
	return pattern


func _get_final_options(initial_options: Dictionary):
	var options = initial_options.duplicate()

	if not "type" in initial_options:
		var inferred_type = FadeTypes.Fade
		for key in shader_exclusive_keys:
			if initial_options.has(key):
				inferred_type = FadeTypes.ShaderFade
		options["type"] = inferred_type

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

	return options


func change_scene(path, setted_options: Dictionary = {}):
	var options = _get_final_options(setted_options)
	yield(_fade_out(options), "completed")
	if not options["no_scene_change"]:
		_replace_scene(path)
	yield(_tree.create_timer(options["wait_time"]), "timeout")
	yield(_fade_in(options), "completed")


func reload_scene(setted_options: Dictionary = {}):
	yield(change_scene(null, setted_options), "completed")


func fade_in_place(setted_options: Dictionary = {}):
	setted_options["no_scene_change"] = true
	yield(change_scene(null, setted_options), "completed")


func _replace_scene(path):
	if path == null:
		# if no path, assume we want a reload
		_tree.reload_current_scene()
		_set_singleton_entities()
		emit_signal("scene_loaded")
		return
	_current_scene.free()
	emit_signal("scene_unloaded")
	var following_scene = ResourceLoader.load(path)
	_current_scene = following_scene.instance()
	_root.add_child(_current_scene)
	_tree.set_current_scene(_current_scene)
	_set_singleton_entities()
	emit_signal("scene_loaded")


func _fade_out(options):
	is_transitioning = true
	_animation_player.playback_speed = options["speed"]

	match options["type"]:
		FadeTypes.Fade:
			_fade_rect.color = options["color"]
			_animation_player.play("ColorFade")

		FadeTypes.ShaderFade:
			_shader_blend_rect.material.set_shader_param(
				"dissolve_texture", options["pattern_enter"]
			)
			_shader_blend_rect.material.set_shader_param("fade_color", options["color"])
			_shader_blend_rect.material.set_shader_param("inverted", false)
			var animation = _animation_player.get_animation("ShaderFade")
			animation.track_set_key_transition(0, 0, options["ease_enter"])
			_animation_player.play("ShaderFade")

	yield(_animation_player, "animation_finished")
	emit_signal("fade_complete")


func _fade_in(options):
	match options["type"]:
		FadeTypes.Fade:
			_animation_player.play_backwards("ColorFade")

		FadeTypes.ShaderFade:
			_shader_blend_rect.material.set_shader_param(
				"dissolve_texture", options["pattern_leave"]
			)
			_shader_blend_rect.material.set_shader_param("inverted", options["invert_on_leave"])
			var animation = _animation_player.get_animation("ShaderFade")
			animation.track_set_key_transition(0, 0, options["ease_leave"])
			_animation_player.play_backwards("ShaderFade")

	yield(_animation_player, "animation_finished")
	is_transitioning = false
	emit_signal("transition_finished")
