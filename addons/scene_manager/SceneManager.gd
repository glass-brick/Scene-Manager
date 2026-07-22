extends Node2D

signal fade_started
signal fade_complete
signal scene_unloaded
signal scene_loaded
signal transition_finished
signal background_load_started(path: String)
signal background_load_progress(path: String, progress: float)
signal background_load_finished(path: String)
signal background_load_failed(path: String)

const SceneTreeAdapter = preload("res://addons/scene_manager/SceneTreeAdapter.gd")
const DEFAULT_LOADING_SCREEN = preload("res://addons/scene_manager/DefaultLoadingScreen.tscn")

var is_transitioning := false
var _adapter
var _current_scene : Node
@onready var _animation_player : AnimationPlayer = $AnimationPlayer
@onready var _shader_blend_rect : ColorRect = $CanvasLayer/ColorRect
@onready var _loading_screen_layer : CanvasLayer = $LoadingScreenLayer

var default_options := {
	"speed": 2,
	"color": Color("#000000"),
	"pattern": "fade",
	"wait_time": 0.5,
	"invert_on_enter": false,
	"invert_on_leave": true,
	"ease": 1.0,
	"skip_scene_change": false,
	"skip_fade_out": false,
	"skip_fade_in": false,
	"background_loading": false,
	"loading_screen": null,
	"min_loading_time": 0.0,
	"cache_mode": ResourceLoader.CACHE_MODE_IGNORE,
	"on_tree_enter": func(scene): null,
	"on_ready": func(scene): null,
	"on_fade_out": func(): null,
	"on_fade_in": func(): null,
}
# extra_options = {
#   "pattern_enter": DEFAULT_IMAGE,
#   "pattern_leave": DEFAULT_IMAGE,
#   "ease_enter": 1.0,
#   "ease_leave": 1.0,
# }

var _previous_scene = null
var _is_swapping := false
var _pending_loads := {}
var _ready_scenes := {}
var _discarded_loads := {}
var _failed_loads := {}

func _ready() -> void:
	if not _adapter:
		_adapter = SceneTreeAdapter.new(get_tree())
	_current_scene = _adapter.get_current_scene()
	scene_loaded.emit()

func _load_pattern(pattern) -> Texture:
	assert(pattern is Texture or pattern is String, "Pattern is not a valid Texture, absolute path, or built-in texture.")
	if pattern is String:
		if pattern.is_absolute_path():
			return load(pattern)
		elif pattern == 'fade':
			return null
		return load("res://addons/scene_manager/shader_patterns/%s.png" % pattern)
	return pattern

func _get_final_options(initial_options: Dictionary) -> Dictionary:
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

func preload_scene(path: String, cache_mode: int = ResourceLoader.CACHE_MODE_IGNORE) -> void:
	if _ready_scenes.has(path) or _pending_loads.has(path):
		return
	_discarded_loads.erase(path)
	_failed_loads.erase(path)
	var error := ResourceLoader.load_threaded_request(path, "PackedScene", false, cache_mode)
	if error != OK:
		push_error("SceneManager: could not start loading %s (error %d)" % [path, error])
		_failed_loads[path] = true
		background_load_failed.emit(path)
		return
	_pending_loads[path] = 0.0
	background_load_started.emit(path)

func is_scene_ready(path: String) -> bool:
	return _ready_scenes.has(path)

func get_load_progress(path: String) -> float:
	if _ready_scenes.has(path):
		return 1.0
	return _pending_loads.get(path, 0.0)

func drop_preloaded_scene(path: String) -> void:
	_ready_scenes.erase(path)
	# Godot cannot cancel a threaded request, so in-flight loads are discarded on arrival.
	if _pending_loads.has(path):
		_discarded_loads[path] = true

func _poll_pending_loads() -> void:
	for path in _pending_loads.keys():
		var progress := []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if not progress.is_empty() and progress[0] != _pending_loads[path]:
			_pending_loads[path] = progress[0]
			background_load_progress.emit(path, progress[0])
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_pending_loads.erase(path)
			var scene = ResourceLoader.load_threaded_get(path)
			if _discarded_loads.erase(path):
				continue
			_ready_scenes[path] = scene
			background_load_progress.emit(path, 1.0)
			background_load_finished.emit(path)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_pending_loads.erase(path)
			_discarded_loads.erase(path)
			_failed_loads[path] = true
			push_error("SceneManager: failed to load %s" % path)
			background_load_failed.emit(path)

func _take_ready_scene(path: String) -> PackedScene:
	var scene = _ready_scenes[path]
	_ready_scenes.erase(path)
	return scene

func _process(_delta: float) -> void:
	_poll_pending_loads()
	# While swapping, the tree still reports the outgoing scene; adopting it here would
	# clobber the instance _replace_scene is about to install.
	if not _adapter or _is_swapping:
		return
	var tree_scene = _adapter.get_current_scene()
	if not is_instance_valid(tree_scene):
		return
	if not is_instance_valid(_previous_scene):
		_previous_scene = tree_scene
		_current_scene = tree_scene
		scene_loaded.emit()
	if tree_scene != _previous_scene:
		_previous_scene = tree_scene

func change_scene(path: Variant, setted_options: Dictionary = {}) -> void:
	assert(path == null or path is String or path is PackedScene, 'Path must be a string or a PackedScene')
	var options = _get_final_options(setted_options)
	# Kick the load before the fade so the two overlap.
	if path is String and _should_load_in_background(options):
		preload_scene(path, options["cache_mode"])
	if not options["skip_fade_out"]:
		await fade_out(setted_options)
	if not options["skip_scene_change"]:
		if path == null:
			await _reload_scene()
		else:
			var following_scene = await _resolve_scene(path, options)
			if following_scene == null:
				if not options["skip_fade_out"]:
					await fade_in(setted_options)
				return
			await _replace_scene(following_scene, options)
	await _adapter.create_timer(options["wait_time"]).timeout
	if not options["skip_fade_in"]:
		await fade_in(setted_options)

func reload_scene(setted_options: Dictionary = {}) -> void:
	await change_scene(null, setted_options)

func _reload_scene() -> void:
	_is_swapping = true
	_adapter.reload_current_scene()
	await _adapter.create_timer(0.0).timeout
	_current_scene = _adapter.get_current_scene()
	_is_swapping = false

func fade_in_place(setted_options: Dictionary = {}) -> void:
	setted_options["skip_scene_change"] = true
	await change_scene(null, setted_options)

func _replace_scene(following_scene: PackedScene, options: Dictionary) -> void:
	_is_swapping = true
	_adapter.free_scene(_current_scene)
	scene_unloaded.emit()
	_current_scene = following_scene.instantiate()
	_current_scene.tree_entered.connect(options["on_tree_enter"].bind(_current_scene))
	_current_scene.ready.connect(options["on_ready"].bind(_current_scene))
	await _adapter.create_timer(0.0).timeout
	_adapter.add_scene(_current_scene)
	_adapter.set_current_scene(_current_scene)
	_is_swapping = false

func _resolve_scene(path: Variant, options: Dictionary) -> PackedScene:
	if path is PackedScene:
		return path
	if not _ready_scenes.has(path) and not _pending_loads.has(path):
		# Don't re-request a load that already failed during this transition's fade out.
		if _failed_loads.erase(path):
			return null
		# A blocking load cannot animate anything, so it never gets a loading screen.
		if not _should_load_in_background(options):
			return ResourceLoader.load(path, "PackedScene", options["cache_mode"])
		preload_scene(path, options["cache_mode"])
		if not _pending_loads.has(path):
			return null

	var loading_screen := _show_loading_screen(options["loading_screen"])
	var started := Time.get_ticks_msec()
	while _pending_loads.has(path):
		_report_progress(loading_screen, get_load_progress(path))
		await _adapter.create_timer(0.0).timeout
	_report_progress(loading_screen, 1.0)

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	if elapsed < options["min_loading_time"]:
		await _adapter.create_timer(options["min_loading_time"] - elapsed).timeout

	if is_instance_valid(loading_screen):
		loading_screen.queue_free()
	return _take_ready_scene(path) if _ready_scenes.has(path) else null

func _should_load_in_background(options: Dictionary) -> bool:
	# A loading screen and a minimum loading time only mean anything while the load runs off
	# the main thread, so asking for either implies background loading.
	return (
		options["background_loading"]
		or options["min_loading_time"] > 0.0
		or _wants_loading_screen(options["loading_screen"])
	)

func _wants_loading_screen(loading_screen: Variant) -> bool:
	if loading_screen is bool:
		return loading_screen
	return loading_screen != null

func _show_loading_screen(loading_screen: Variant) -> Node:
	if not _wants_loading_screen(loading_screen):
		return null
	if loading_screen is bool:
		loading_screen = DEFAULT_LOADING_SCREEN
	assert(loading_screen is PackedScene, "loading_screen must be a PackedScene, true, or null")
	var instance = loading_screen.instantiate()
	_loading_screen_layer.add_child(instance)
	return instance

func _report_progress(loading_screen: Node, progress: float) -> void:
	if is_instance_valid(loading_screen) and loading_screen.has_method("set_progress"):
		loading_screen.set_progress(progress)

func fade_out(setted_options: Dictionary= {}) -> void:
	var options = _get_final_options(setted_options)
	is_transitioning = true
	_animation_player.speed_scale = options["speed"]

	_shader_blend_rect.material.set_shader_parameter(
		"dissolve_texture", options["pattern_enter"]
	)
	_shader_blend_rect.material.set_shader_parameter("fade", !options["pattern_enter"])
	_shader_blend_rect.material.set_shader_parameter("fade_color", options["color"])
	_shader_blend_rect.material.set_shader_parameter("inverted", options["invert_on_enter"])
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_enter"])
	fade_started.emit()
	_animation_player.play("ShaderFade")

	await _animation_player.animation_finished
	fade_complete.emit()
	options["on_fade_out"].call()

func fade_in(setted_options: Dictionary = {}) -> void:
	var options = _get_final_options(setted_options)
	_animation_player.speed_scale = options["speed"]
	_shader_blend_rect.material.set_shader_parameter(
		"dissolve_texture", options["pattern_leave"]
	)
	_shader_blend_rect.material.set_shader_parameter("fade", !options["pattern_leave"])
	_shader_blend_rect.material.set_shader_parameter("fade_color", options["color"])
	_shader_blend_rect.material.set_shader_parameter("inverted", options["invert_on_leave"])
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_leave"])
	fade_started.emit()
	_animation_player.play_backwards("ShaderFade")

	await _animation_player.animation_finished
	is_transitioning = false
	transition_finished.emit()
	options["on_fade_in"].call()
