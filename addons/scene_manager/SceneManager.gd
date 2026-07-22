extends Node2D
## Scene transitions with animated fades, a drop-in replacement for
## [method SceneTree.change_scene_to_file].
##
## Autoloaded as [code]SceneManager[/code], so it is reachable from anywhere without a
## preload. Every method takes an options dictionary merged over [member default_options],
## so a call only names the keys it changes:
## [codeblock]
## SceneManager.change_scene("res://levels/two.tscn", { "pattern": "squares" })
## [/codeblock]
## Large scenes can be loaded off the main thread so the load overlaps the fade instead of
## stalling it, optionally behind a loading screen:
## [codeblock]
## SceneManager.change_scene("res://levels/big.tscn", {
##     "loading_screen": true,
##     "min_loading_time": 1.0,
## })
## [/codeblock]
## Use [method preload_scene] to start that load earlier still. Every method can be awaited
## to continue once the transition is over.
##
## @tutorial(Full documentation): https://github.com/glass-brick/Scene-Manager/wiki

## Emitted when a fade begins, in either direction.
signal fade_started
## Emitted when a fade out ends, with the screen fully covered.
signal fade_complete
## Emitted after the outgoing scene has been freed.
signal scene_unloaded
## Emitted once a new scene is in the tree. Also fires for scene changes made by other code,
## such as a direct [method SceneTree.change_scene_to_file] call.
signal scene_loaded
## Emitted when a transition is completely over and the screen is clear again.
signal transition_finished
## Emitted when a threaded load of [param path] starts.
signal background_load_started(path: String)
## Reports threaded loading progress for [param path], from 0.0 to 1.0. Emitted per path,
## since several loads can be in flight at once.
signal background_load_progress(path: String, progress: float)
## Emitted when [param path] has finished loading and is ready to be swapped in.
signal background_load_finished(path: String)
## Emitted when [param path] failed to load. The scene swap is abandoned and the screen
## fades back in rather than stranding the player behind an opaque overlay.
signal background_load_failed(path: String)

const SceneTreeAdapter = preload("res://addons/scene_manager/SceneTreeAdapter.gd")
## The loading screen used when [code]loading_screen[/code] is [code]true[/code]: a progress
## bar centred on a transparent background.
const DEFAULT_LOADING_SCREEN = preload("res://addons/scene_manager/DefaultLoadingScreen.tscn")

## [code]true[/code] while a transition is running. Check it before starting another one, so
## a button mashed twice cannot fire two overlapping transitions.
var is_transitioning := false
var _adapter
var _current_scene: Node
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _shader_blend_rect: ColorRect = $CanvasLayer/ColorRect
@onready var _loading_screen_layer: CanvasLayer = $LoadingScreenLayer

## Options used by every call, each one overridden by the dictionary passed to a method.
## Assign to this to change the defaults for the whole project.
## [br][br]
## [code]speed[/code]: multiplier on the one second fade animation.[br]
## [code]color[/code]: the [Color] the screen fades to.[br]
## [code]pattern[/code]: [code]"fade"[/code] for a flat alpha fade, or the name of a mask in
## [code]shader_patterns/[/code], or an absolute path to a texture.[br]
## [code]wait_time[/code]: seconds to hold the covered screen between the two fades.[br]
## [code]invert_on_enter[/code], [code]invert_on_leave[/code]: reverse the direction the
## pattern dissolves in.[br]
## [code]ease[/code]: curve of the fade; 1.0 is linear, lower eases out, higher eases in.[br]
## [code]skip_scene_change[/code], [code]skip_fade_out[/code], [code]skip_fade_in[/code]:
## leave that part of the transition out.[br]
## [code]background_loading[/code]: load the scene on a worker thread, overlapping the
## fade out instead of blocking it.[br]
## [code]loading_screen[/code]: a [PackedScene] to show while loading, or [code]true[/code]
## for [constant DEFAULT_LOADING_SCREEN]. Implies [code]background_loading[/code].[br]
## [code]min_loading_time[/code]: seconds to keep the loading screen up, so a fast load does
## not make it flash past. Implies [code]background_loading[/code].[br]
## [code]cache_mode[/code]: the [enum ResourceLoader.CacheMode] to load with.[br]
## [code]on_tree_enter[/code], [code]on_ready[/code]: [Callable]s handed the new scene, to
## set it up before it runs.[br]
## [code]on_fade_out[/code], [code]on_fade_in[/code]: [Callable]s run as each fade ends.
## [br][br]
## [code]pattern[/code] and [code]ease[/code] each apply to both halves of the transition.
## To differ per side, pass [code]pattern_enter[/code] / [code]pattern_leave[/code] or
## [code]ease_enter[/code] / [code]ease_leave[/code] instead, which take priority.
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
	"on_tree_enter": func(scene): return,
	"on_ready": func(scene): return,
	"on_fade_out": func(): return,
	"on_fade_in": func(): return,
}
var _previous_scene = null
var _is_swapping := false
var _pending_loads := { }
var _ready_scenes := { }
var _discarded_loads := { }
var _failed_loads := { }


func _ready() -> void:
	if not _adapter:
		_adapter = SceneTreeAdapter.new(get_tree())
	_current_scene = _adapter.get_current_scene()
	scene_loaded.emit()


func _load_pattern(pattern) -> Texture:
	assert(
			pattern is Texture or pattern is String,
			"Pattern is not a valid Texture, absolute path, or built-in texture.",
	)
	if pattern is String:
		if pattern.is_absolute_path():
			return load(pattern)
		if pattern == 'fade':
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


## Starts loading [param path] on a worker thread so a later [method change_scene] can swap
## it in with no wait. Does nothing if that scene is already loaded or in flight.
## [br][br]
## Track it with [signal background_load_progress] and [signal background_load_finished], or
## poll [method get_load_progress] and [method is_scene_ready].
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


## Returns [code]true[/code] if [param path] has finished preloading and is waiting to be
## handed over.
func is_scene_ready(path: String) -> bool:
	return _ready_scenes.has(path)


## Returns how far along the threaded load of [param path] is, from 0.0 to 1.0. Returns 1.0
## once the scene is ready, and 0.0 for a path that was never requested.
func get_load_progress(path: String) -> float:
	if _ready_scenes.has(path):
		return 1.0
	return _pending_loads.get(path, 0.0)


## Throws away a scene kept by [method preload_scene], freeing the memory it holds.
## [br][br]
## Godot cannot cancel a threaded request, so a load still in flight is not stopped: it is
## marked and discarded the moment it arrives.
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


## Swaps in a new scene, fading out before the swap and back in after it. Await it to
## continue once the whole transition is over.
## [br][br]
## [param path] takes a [String] path, an already loaded [PackedScene], or [code]null[/code]
## to reload the current scene. [param setted_options] is merged over
## [member default_options].
## [br][br]
## If the load fails the swap is abandoned and the screen fades back in, leaving the current
## scene running.
func change_scene(path: Variant, setted_options: Dictionary = { }) -> void:
	assert(
			path == null or path is String or path is PackedScene,
			'Path must be a string or a PackedScene',
	)
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


## Reloads the current scene from disk, with the same transition [method change_scene] uses.
func reload_scene(setted_options: Dictionary = { }) -> void:
	await change_scene(null, setted_options)


func _reload_scene() -> void:
	_is_swapping = true
	_adapter.reload_current_scene()
	await _adapter.create_timer(0.0).timeout
	_current_scene = _adapter.get_current_scene()
	_is_swapping = false


## Fades out and back in without changing scene, useful for covering work done in an
## [code]on_fade_out[/code] callable such as repositioning the player.
func fade_in_place(setted_options: Dictionary = { }) -> void:
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
	var min_loading_time: float = options["min_loading_time"]
	var started := Time.get_ticks_msec()
	# The bar tracks whichever is slower, the real load or the minimum time, so a scene that
	# loads instantly still fills over min_loading_time instead of snapping to full.
	while true:
		var elapsed := (Time.get_ticks_msec() - started) / 1000.0
		var time_progress := 1.0 if min_loading_time <= 0.0 else minf(
				elapsed / min_loading_time,
				1.0,
		)
		_report_progress(loading_screen, minf(get_load_progress(path), time_progress))
		if not _pending_loads.has(path) and elapsed >= min_loading_time:
			break
		await _adapter.create_timer(0.0).timeout

	if is_instance_valid(loading_screen):
		loading_screen.queue_free()
	return _take_ready_scene(path) if _ready_scenes.has(path) else null


func _should_load_in_background(options: Dictionary) -> bool:
	# A loading screen and a minimum loading time only mean anything while the load runs off
	# the main thread, so asking for either implies background loading.
	return (
		options["background_loading"] or options["min_loading_time"] > 0.0
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


## Covers the screen, playing the fade forwards. Await it to continue once the screen is
## fully hidden. Pair it with [method fade_in] to drive a transition by hand.
func fade_out(setted_options: Dictionary = { }) -> void:
	var options = _get_final_options(setted_options)
	is_transitioning = true
	_animation_player.speed_scale = options["speed"]

	_shader_blend_rect.material.set_shader_parameter("dissolve_texture", options["pattern_enter"])
	_shader_blend_rect.material.set_shader_parameter("fade", ! options["pattern_enter"])
	_shader_blend_rect.material.set_shader_parameter("fade_color", options["color"])
	_shader_blend_rect.material.set_shader_parameter("inverted", options["invert_on_enter"])
	var animation = _animation_player.get_animation("ShaderFade")
	animation.track_set_key_transition(0, 0, options["ease_enter"])
	fade_started.emit()
	_animation_player.play("ShaderFade")

	await _animation_player.animation_finished
	fade_complete.emit()
	options["on_fade_out"].call()


## Reveals the screen again, playing the fade backwards. Await it to continue once the
## screen is clear.
func fade_in(setted_options: Dictionary = { }) -> void:
	var options = _get_final_options(setted_options)
	_animation_player.speed_scale = options["speed"]
	_shader_blend_rect.material.set_shader_parameter("dissolve_texture", options["pattern_leave"])
	_shader_blend_rect.material.set_shader_parameter("fade", ! options["pattern_leave"])
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
