extends Node2D

signal fade_complete
signal scene_unloaded
signal scene_loaded
signal transition_finished

var is_transitioning : bool = false
@onready var _tree := get_tree()
@onready var _root := _tree.get_root()
@onready var _current_scene := _tree.current_scene
@onready var _animation_player := $AnimationPlayer
@onready var _shader_blend_rect := $CanvasLayer/ShaderFade

var default_options = {
	"speed": 2,
	"color": Color("#000000"),
	"pattern": "fade",
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

var singleton_entities = {}


func _ready():
	_set_singleton_entities()
	call_deferred("emit_signal", "scene_loaded")
	call_deferred("emit_signal", "transition_finished")


func _set_singleton_entities():
	singleton_entities = {}
	var entities = _current_scene.get_tree().get_nodes_in_group(
		SceneManagerConstants.SINGLETON_GROUP_NAME
	)
	for entity in entities:
		var has_entity_name : bool = entity.has_meta(SceneManagerConstants.SINGLETON_META_NAME)
		assert(has_entity_name,"The node was set as a singleton entity, but no entity name was provided.")
		var entity_name = entity.get_meta(SceneManagerConstants.SINGLETON_META_NAME)
		assert(not singleton_entities.has(entity_name),"The entity name %s is already being used more than once! Please check that your entity name is unique within the scene.")
		singleton_entities[entity_name] = entity


func get_entity(entity_name: String):
	assert(singleton_entities.has(entity_name),"Entity is not set as a singleton entity. Please define it in the editor.")
	return singleton_entities[entity_name]


func _load_pattern(pattern):
	assert(pattern is Texture or pattern is String, "Pattern is not a valid Texture, absolute path, or built-in texture.")
	if pattern is String:
		if pattern.is_absolute_path():
			return load(pattern)
		elif pattern == 'fade':
			return null
		return load("res://addons/scene_manager/shader_patterns/%s.png" % pattern)
	return pattern


func _get_final_options(initial_options: Dictionary):
	var options = initial_options.duplicate()

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


var _previous_scene = null


func _process(_delta):
	if not is_instance_valid(_previous_scene) and _tree.current_scene:
		_previous_scene = _tree.current_scene
		_current_scene = _tree.current_scene
		_set_singleton_entities()
		emit_signal("scene_loaded")
	if _tree.current_scene != _previous_scene:
		_previous_scene = _tree.current_scene


func change_scene(path, setted_options: Dictionary = {}):
	var options = _get_final_options(setted_options)
	_fade_out(options)
	await fade_complete
	if not options["no_scene_change"]:
		_replace_scene(path)
	await _tree.create_timer(options["wait_time"]).timeout
	_fade_in(options)

	await transition_finished



func reload_scene(setted_options: Dictionary = {}):
	change_scene(null, setted_options)
	await fade_complete

func fade_in_place(setted_options: Dictionary = {}):
	setted_options["no_scene_change"] = true
	change_scene(null, setted_options)
	await fade_complete

func _replace_scene(path):
	if path == null:
		# if no path, assume we want a reload
		_tree.reload_current_scene()
		await _tree.create_timer(0.0).timeout
		_current_scene = _tree.current_scene
		return
	_current_scene.free()
	emit_signal("scene_unloaded")
	var following_scene: PackedScene = ResourceLoader.load(path, "PackedScene", 0)
	_current_scene = following_scene.instantiate()
	await _tree.create_timer(0.0).timeout
	_root.add_child(_current_scene)
	_tree.set_current_scene(_current_scene)


func _fade_out(options):
	is_transitioning = true
	_animation_player.playback_speed = options["speed"]

	_shader_blend_rect.material.set_shader_param(
		"dissolve_texture", options["pattern_enter"]
	)
	_shader_blend_rect.material.set_shader_param("fade", !options["pattern_enter"])
	_shader_blend_rect.material.set_shader_param("fade_color", options["color"])
	_shader_blend_rect.material.set_shader_param("inverted", false)
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_enter"])
	_animation_player.play("ShaderFade")

	await _animation_player.animation_finished
	emit_signal("fade_complete")


func _fade_in(options):
	_shader_blend_rect.material.set_shader_param(
		"dissolve_texture", options["pattern_leave"]
	)
	_shader_blend_rect.material.set_shader_param("fade", !options["pattern_leave"])
	_shader_blend_rect.material.set_shader_param("inverted", options["invert_on_leave"])
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_leave"])
	_animation_player.play_backwards("ShaderFade")

	await _animation_player.animation_finished
	is_transitioning = false
	emit_signal("transition_finished")
