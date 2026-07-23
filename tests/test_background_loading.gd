extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const SCENE_A = "res://tests/fixtures/scene_a.tscn"
const SCENE_B = "res://tests/fixtures/scene_b.tscn"
const MISSING = "res://tests/fixtures/does_not_exist.tscn"

var _harness
var _manager
var _adapter


func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager
	_adapter = _harness.adapter


func after_each():
	await wait_process_frames(1)


func test_preload_scene_makes_the_scene_ready():
	assert_false(_manager.is_scene_ready(SCENE_A))
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	assert_true(_manager.is_scene_ready(SCENE_A))
	assert_eq(_manager.get_load_progress(SCENE_A), 1.0)


func test_preload_emits_started_and_finished():
	watch_signals(_manager)
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	assert_signal_emitted_with_parameters(_manager, "background_load_started", [SCENE_A])
	assert_signal_emitted_with_parameters(_manager, "background_load_finished", [SCENE_A])


func test_preload_reports_progress():
	watch_signals(_manager)
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	var reports = get_signal_parameters(_manager, "background_load_progress")
	assert_eq(reports[0], SCENE_A, "progress is reported per path")
	assert_eq(reports[1], 1.0, "the last report is a completed load")


func test_preloading_the_same_path_twice_is_a_no_op():
	watch_signals(_manager)
	_manager.preload_scene(SCENE_A)
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	assert_eq(get_signal_emit_count(_manager, "background_load_started"), 1)


func test_change_scene_consumes_a_preloaded_scene():
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)

	watch_signals(_manager)
	await _manager.change_scene(SCENE_A, _harness.options())
	assert_eq(_adapter.added_scenes[0].name, "SceneA")
	assert_false(_manager.is_scene_ready(SCENE_A), "the preloaded scene should be handed over")
	assert_signal_not_emitted(_manager, "background_load_started", "no second request")


func test_background_loading_option_loads_and_swaps():
	await _manager.change_scene(SCENE_A, _harness.options({ "background_loading": true }))
	assert_eq(_adapter.added_scenes.size(), 1)
	assert_eq(_adapter.added_scenes[0].name, "SceneA")


func test_background_loading_starts_before_the_fade_completes():
	var order := []
	_manager.background_load_started.connect(func(_path): order.append("load_started"))
	_manager.fade_complete.connect(func(): order.append("fade_complete"))
	await _manager.change_scene(SCENE_A, _harness.options({ "background_loading": true }))
	assert_eq(order[0], "load_started", "the load must overlap the fade, not follow it")
	assert_true(order.has("fade_complete"))


func test_drop_preloaded_scene_discards_a_ready_scene():
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	_manager.drop_preloaded_scene(SCENE_A)
	assert_false(_manager.is_scene_ready(SCENE_A))
	assert_eq(_manager.get_load_progress(SCENE_A), 0.0)


func test_drop_preloaded_scene_discards_an_in_flight_load():
	_manager.preload_scene(SCENE_B)
	_manager.drop_preloaded_scene(SCENE_B)
	await wait_process_frames(5)
	assert_false(_manager.is_scene_ready(SCENE_B), "a discarded load must not be kept")


func _consume_missing_file_errors():
	# Godot's loader logs its own errors for a missing file; they are expected here.
	for error in get_errors():
		error.handled = true


func test_missing_scene_reports_a_failure():
	watch_signals(_manager)
	_manager.preload_scene(MISSING)
	await wait_for_signal(_manager.background_load_failed, 5)
	assert_signal_emitted_with_parameters(_manager, "background_load_failed", [MISSING])
	assert_push_error("failed to load")
	assert_false(_manager.is_scene_ready(MISSING))
	_consume_missing_file_errors()


func test_a_failed_load_aborts_the_swap_and_fades_back_in():
	await _manager.change_scene(MISSING, _harness.options({ "background_loading": true }))
	assert_push_error("failed to load")
	_consume_missing_file_errors()
	assert_eq(_adapter.added_scenes, [], "nothing should be swapped in")
	assert_eq(_adapter.freed_scenes, [], "the current scene must survive a failed load")
	assert_false(_manager.is_transitioning, "the player must not be left behind a black screen")
	assert_almost_eq(
			_harness.shader_param("dissolve_amount"),
			0.0,
			0.001,
			"screen should be clear again",
	)
