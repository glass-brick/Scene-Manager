extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const LoadingScreenFixture = preload("res://tests/fixtures/loading_screen.gd")
const LOADING_SCREEN = preload("res://tests/fixtures/loading_screen.tscn")
const SCENE_A = "res://tests/fixtures/scene_a.tscn"

var _harness
var _manager
var _adapter


func before_each():
	LoadingScreenFixture.reset()
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager
	_adapter = _harness.adapter


func after_each():
	await wait_process_frames(1)


func test_loading_screen_is_shown_during_a_background_load():
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"background_loading": true,
						"loading_screen": LOADING_SCREEN,
					}),
	)
	assert_eq(LoadingScreenFixture.instantiated_count, 1)


func test_loading_screen_receives_progress_ending_at_one():
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"background_loading": true,
						"loading_screen": LOADING_SCREEN,
					}),
	)
	var reports = LoadingScreenFixture.progress_reports
	assert_gt(reports.size(), 0, "set_progress should be called")
	assert_eq(reports[-1], 1.0, "the last report should be a completed load")


func test_loading_screen_is_removed_before_the_transition_ends():
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"background_loading": true,
						"loading_screen": LOADING_SCREEN,
					}),
	)
	assert_eq(LoadingScreenFixture.removed_count, 1, "loading screen should be torn down")
	assert_eq(_manager._loading_screen_layer.get_child_count(), 0)


func test_loading_screen_sits_above_the_fade_overlay():
	var fade_layer = _manager.get_node("CanvasLayer")
	assert_gt(
			_manager._loading_screen_layer.layer,
			fade_layer.layer,
			"an opaque fade would hide the loading screen otherwise",
	)


func test_no_loading_screen_when_the_option_is_unset():
	await _manager.change_scene(SCENE_A, _harness.options({ "background_loading": true }))
	assert_eq(LoadingScreenFixture.instantiated_count, 0)


func test_asking_for_a_loading_screen_is_enough():
	# A loading screen is meaningless during a blocking load, so requesting one has to imply
	# background loading — otherwise the option silently does nothing.
	await _manager.change_scene(SCENE_A, _harness.options({ "loading_screen": LOADING_SCREEN }))
	assert_eq(LoadingScreenFixture.instantiated_count, 1)
	assert_eq(_adapter.added_scenes[0].name, "SceneA")


func test_min_loading_time_alone_is_also_enough():
	var started := Time.get_ticks_msec()
	await _manager.change_scene(SCENE_A, _harness.options({ "min_loading_time": 0.3 }))
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	assert_gt(elapsed, 0.3, "min_loading_time must be honoured without background_loading")


func test_a_background_loading_disabled_change_scene_loads_synchronously():
	watch_signals(_manager)
	await _manager.change_scene(SCENE_A, _harness.options({ "background_loading": false }))
	assert_signal_not_emitted(
			_manager,
			"background_load_started",
			"no threaded load when nothing asks for one",
	)
	assert_eq(LoadingScreenFixture.instantiated_count, 0)


func test_progress_ramps_across_min_loading_time_instead_of_snapping():
	# A fixture scene loads instantly, so without blending in elapsed time the bar would jump
	# straight to full and then sit there for the whole min_loading_time.
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"loading_screen": LOADING_SCREEN,
						"min_loading_time": 0.4,
					}),
	)
	var reports = LoadingScreenFixture.progress_reports
	assert_gt(reports.size(), 5, "progress should be reported every frame")
	assert_lt(reports[0], 0.5, "should start near empty")
	assert_eq(reports[-1], 1.0, "and end full")

	var partial := 0
	for value in reports:
		if value > 0.0 and value < 1.0:
			partial += 1
	assert_gt(partial, 3, "expected intermediate values, got %s" % [reports])


func test_progress_never_goes_backwards():
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"loading_screen": LOADING_SCREEN,
						"min_loading_time": 0.3,
					}),
	)
	var reports = LoadingScreenFixture.progress_reports
	for i in range(1, reports.size()):
		assert_true(
				reports[i] >= reports[i - 1],
				"progress went backwards at %d: %s" % [i, reports],
		)


func test_min_loading_time_keeps_a_fast_load_on_screen():
	var started := Time.get_ticks_msec()
	await _manager.change_scene(
			SCENE_A,
			_harness.options(
					{
						"background_loading": true,
						"loading_screen": LOADING_SCREEN,
						"min_loading_time": 0.3,
					}
			),
	)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	assert_gt(elapsed, 0.3, "the loading screen should not flash past")
	assert_eq(LoadingScreenFixture.removed_count, 1)


func test_true_resolves_to_the_shipped_default_loading_screen():
	var screen = _manager._show_loading_screen(true)
	assert_not_null(screen, "true should select the bundled loading screen")
	assert_eq(screen.scene_file_path, "res://addons/scene_manager/DefaultLoadingScreen.tscn")
	assert_true(screen.has_method("set_progress"), "the manager drives it through set_progress")
	screen.free()


func test_false_and_null_show_nothing():
	assert_null(_manager._show_loading_screen(false))
	assert_null(_manager._show_loading_screen(null))


func test_default_loading_screen_drives_its_progress_bar():
	var screen = _manager.DEFAULT_LOADING_SCREEN.instantiate()
	add_child_autofree(screen)
	var bar = screen.get_node("CenterContainer/ProgressBar")
	screen.set_progress(0.5)
	assert_eq(bar.value, bar.max_value * 0.5)
	screen.set_progress(1.0)
	assert_eq(bar.value, bar.max_value)


func test_a_transition_with_the_default_loading_screen_cleans_up():
	await _manager.change_scene(
			SCENE_A,
			_harness.options(
					{
						"background_loading": true,
						"loading_screen": true,
						"min_loading_time": 0.2,
					}
			),
	)
	assert_eq(LoadingScreenFixture.instantiated_count, 0, "should not be the test fixture")
	assert_eq(_manager._loading_screen_layer.get_child_count(), 0)
	assert_eq(_adapter.added_scenes[0].name, "SceneA")


func test_preloaded_scenes_still_get_a_loading_screen():
	_manager.preload_scene(SCENE_A)
	await wait_for_signal(_manager.background_load_finished, 5)
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"loading_screen": LOADING_SCREEN,
						"min_loading_time": 0.1,
					}),
	)
	assert_eq(LoadingScreenFixture.instantiated_count, 1)
	assert_eq(LoadingScreenFixture.removed_count, 1)
