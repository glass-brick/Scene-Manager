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
## [br][br]
## Defaults live under [code]Project > Project Settings > Scene Manager[/code], and
## [method set_animation_player] swaps the built-in shader fade for animations of your own.
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
const SceneManagerSettings = preload("res://addons/scene_manager/SceneManagerSettings.gd")
## The loading screen used when [code]loading_screen[/code] is [code]true[/code]: a progress
## bar centred on a transparent background.
const DEFAULT_LOADING_SCREEN = preload("res://addons/scene_manager/DefaultLoadingScreen.tscn")
## The animation every transition plays by default, on the built-in player and on a custom one
## alike. A player set through [method set_animation_player] takes over the whole transition
## simply by defining an animation with this name.
const DEFAULT_ANIMATION_NAME := "Fade"

## [code]true[/code] while a transition is running. Check it before starting another one, so
## a button mashed twice cannot fire two overlapping transitions.
var is_transitioning := false
var _adapter
var _current_scene: Node
var _user_animation_player: AnimationPlayer
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _shader_blend_rect: ColorRect = $CanvasLayer/ColorRect
@onready var _loading_screen_layer: CanvasLayer = $LoadingScreenLayer

## Options used by every call, check full docs [here](https://github.com/glass-brick/Scene-Manager/wiki/Transition-Options)
var default_options := SceneManagerSettings.build_defaults()
var _previous_scene = null
var _is_swapping := false
var _pending_loads := { }
var _ready_scenes := { }
var _discarded_loads := { }
var _failed_loads := { }


func _ready() -> void:
	var configured_player := SceneManagerSettings.get_animation_player_path()
	if not configured_player.is_empty():
		set_animation_player(configured_player)
	if not _adapter:
		_adapter = SceneTreeAdapter.new(get_tree())
	_current_scene = _adapter.get_current_scene()
	scene_loaded.emit()


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


## Covers the screen, playing the fade forwards. Await it to continue once the screen is
## fully hidden. Pair it with [method fade_in] to drive a transition by hand, or with
## [code]skip_fade_out[/code] to get work done while the screen is covered:
## [codeblock]
## await SceneManager.fade_out()
## # ... reposition the player, save the game, whatever needs hiding ...
## SceneManager.change_scene("res://levels/two.tscn", { "skip_fade_out": true })
## [/codeblock]
## Reads [code]speed[/code], [code]color[/code], [code]pattern_enter[/code],
## [code]invert_on_enter[/code], [code]ease_enter[/code] and
## [code]animation_name_enter[/code]; the rest of the options do not apply.
func fade_out(setted_options: Dictionary = { }) -> void:
	var options = _get_final_options(setted_options)
	var fade := _resolve_fade(options["animation_name_enter"])
	var player: AnimationPlayer = fade["player"]
	is_transitioning = true
	player.speed_scale = options["speed"]
	if player == _animation_player:
		_setup_builtin_fade(
			options["pattern_enter"],
			options["color"],
			options["invert_on_enter"],
			options["ease_enter"],
		)
	fade_started.emit()
	player.play(fade["animation"])

	await player.animation_finished
	fade_complete.emit()
	options["on_fade_out"].call()


## Reveals the screen again, playing the fade backwards. Await it to continue once the
## screen is clear — useful on its own for an opening transition when the game starts.
## [br][br]
## Reads [code]speed[/code], [code]color[/code], [code]pattern_leave[/code],
## [code]invert_on_leave[/code], [code]ease_leave[/code] and
## [code]animation_name_leave[/code]; the rest of the options do not apply.
func fade_in(setted_options: Dictionary = { }) -> void:
	var options = _get_final_options(setted_options)
	var fade := _resolve_fade(options["animation_name_leave"])
	var player: AnimationPlayer = fade["player"]
	player.speed_scale = options["speed"]
	_clear_inactive_player(player)
	if player == _animation_player:
		_setup_builtin_fade(
			options["pattern_leave"],
			options["color"],
			options["invert_on_leave"],
			options["ease_leave"],
		)
	fade_started.emit()
	player.play_backwards(fade["animation"])

	await player.animation_finished
	is_transitioning = false
	transition_finished.emit()
	options["on_fade_in"].call()


## Fades out and back in without changing scene, useful for covering work done in an
## [code]on_fade_out[/code] callable such as repositioning the player.
func fade_in_place(setted_options: Dictionary = { }) -> void:
	setted_options["skip_scene_change"] = true
	await change_scene(null, setted_options)


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

	for animation_name_key in ["animation_name_enter", "animation_name_leave"]:
		if not animation_name_key in options:
			options[animation_name_key] = options["animation_name"]

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


func _reload_scene() -> void:
	_is_swapping = true
	_adapter.reload_current_scene()
	await _adapter.create_timer(0.0).timeout
	_current_scene = _adapter.get_current_scene()
	_is_swapping = false


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
		var time_progress := (
			1.0
			if min_loading_time <= 0.0
			else minf(elapsed / min_loading_time, 1.0)
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


## Registers a custom [AnimationPlayer] so a project can transition with its own animations
## instead of the built-in shader fade.
## [br][br]
## [param animation_player] is a path to a scene, or an already loaded [PackedScene], whose
## [b]root[/b] node is an [AnimationPlayer]. Pass [code]null[/code] to go back to the built-in
## fade. SceneManager instantiates the scene and holds on to it, so it outlives the scene swaps
## it animates. It can also be set once under
## [code]Project > Project Settings > Scene Manager[/code].
## [br][br]
## The scene must set [member AnimationMixer.root_node] to [code]NodePath(".")[/code] so its
## tracks resolve against itself, and should carry a [code]RESET[/code] animation that parks
## every visual offscreen, since the player is always rendered over the game.
## [br][br]
## An animation named [constant DEFAULT_ANIMATION_NAME] takes over every transition on its own.
## Any other animation is opt-in per call and per side, through the [code]animation_name[/code],
## [code]animation_name_enter[/code] and [code]animation_name_leave[/code] options:
## [codeblock]
## SceneManager.set_animation_player("res://transitions/roll.tscn")
## SceneManager.change_scene("res://levels/two.tscn", {
##     "animation_name_enter": "roll",  # custom animation covers the screen
##     "pattern_leave": "squares",      # built-in shader fade reveals it
## })
## [/codeblock]
## Passing [code]null[/code] for a side forces the built-in fade there. Whichever of the two is
## not animating is cleared instantly the moment the other takes over.
## [br][br]
## Only [code]speed[/code] applies to custom animations: [code]pattern[/code],
## [code]color[/code], [code]invert_on_*[/code] and [code]ease[/code] shape the built-in shader
## fade alone.
func set_animation_player(animation_player: Variant) -> void:
	assert(
		animation_player == null or animation_player is String or animation_player is PackedScene,
		"set_animation_player() takes a scene path, a PackedScene, or null",
	)
	if is_instance_valid(_user_animation_player):
		_user_animation_player.queue_free()
	_user_animation_player = null
	if animation_player == null:
		return
	var scene = animation_player if animation_player is PackedScene else load(animation_player)
	assert(scene is PackedScene, "%s is not a PackedScene" % animation_player)
	var instance = scene.instantiate()
	assert(
		instance is AnimationPlayer,
		"The root of a custom animation player scene must be an AnimationPlayer",
	)
	_user_animation_player = instance
	$CanvasLayer.add_child(_user_animation_player)
	if _user_animation_player.has_animation("RESET"):
		_user_animation_player.play("RESET")


## Picks the player and animation a side of the transition runs on. The custom player only
## wins when it actually has the requested animation, so a player that defines nothing but
## [code]roll[/code] leaves untouched calls on the built-in fade.
func _resolve_fade(animation_name) -> Dictionary:
	var builtin := { "player": _animation_player, "animation": DEFAULT_ANIMATION_NAME }
	if animation_name == null:
		return builtin
	if (
		is_instance_valid(_user_animation_player)
		and _user_animation_player.has_animation(animation_name)
	):
		return { "player": _user_animation_player, "animation": animation_name }
	assert(
		animation_name == DEFAULT_ANIMATION_NAME,
		'No animation named "%s" on the custom animation player.' % animation_name,
	)
	return builtin


func _setup_builtin_fade(pattern, color: Color, inverted: bool, ease_amount: float) -> void:
	_shader_blend_rect.material.set_shader_parameter("dissolve_texture", pattern)
	_shader_blend_rect.material.set_shader_parameter("fade", !pattern)
	_shader_blend_rect.material.set_shader_parameter("fade_color", color)
	_shader_blend_rect.material.set_shader_parameter("inverted", inverted)
	var animation = _animation_player.get_animation(DEFAULT_ANIMATION_NAME)
	animation.track_set_key_transition(0, 0, ease_amount)


## When the two halves of a transition run on different players, the one that covered the
## screen is still covering it. Clear it in one cut so the other can reveal.
func _clear_inactive_player(active: AnimationPlayer) -> void:
	if active != _animation_player:
		_shader_blend_rect.material.set_shader_parameter("dissolve_amount", 0.0)
	elif is_instance_valid(_user_animation_player) and _user_animation_player.has_animation("RESET"):
		_user_animation_player.play("RESET")
