extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const SCENE_A = "res://tests/fixtures/scene_a.tscn"

var _harness
var _manager
var _adapter


func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager
	_adapter = _harness.adapter


func after_each():
	# A finished transition resumes inside AnimationPlayer's animation_finished emission;
	# let that unwind before GUT frees the manager out from under it.
	await wait_process_frames(1)


func test_change_scene_frees_the_old_scene_and_installs_the_new_one():
	var old_scene = _harness.initial_scene
	await _manager.change_scene(SCENE_A, _harness.options())
	assert_eq(_adapter.freed_scenes, [old_scene], "old scene should be freed")
	assert_eq(_adapter.added_scenes.size(), 1)
	assert_eq(_adapter.added_scenes[0].name, "SceneA")
	assert_eq(_adapter.set_current_scene_calls, _adapter.added_scenes)


func test_change_scene_accepts_a_packed_scene():
	# Regression: PR #30 added PackedScene support alongside string paths.
	await _manager.change_scene(load(SCENE_A), _harness.options())
	assert_eq(_adapter.added_scenes.size(), 1)
	assert_eq(_adapter.added_scenes[0].name, "SceneA")


func test_the_new_scene_is_in_the_tree_before_change_scene_returns():
	await _manager.change_scene(SCENE_A, _harness.options())
	assert_eq(_adapter.added_scenes.size(), 1, "swap must complete before the await resolves")
	assert_true(_adapter.added_scenes[0].is_inside_tree())


func test_skip_scene_change_leaves_the_current_scene_alone():
	await _manager.change_scene(SCENE_A, _harness.options({ "skip_scene_change": true }))
	assert_eq(_adapter.freed_scenes, [])
	assert_eq(_adapter.added_scenes, [])


func test_reload_scene_asks_the_tree_to_reload():
	await _manager.reload_scene(_harness.options())
	assert_eq(_adapter.reload_count, 1)
	assert_eq(_adapter.added_scenes, [], "reloading is the tree's job, not a manual swap")


func test_fade_in_place_does_not_reload():
	# Regression: PR #32 — fade_in_place used to reload the scene underneath the fade.
	await _manager.fade_in_place(_harness.options())
	assert_eq(_adapter.reload_count, 0)
	assert_eq(_adapter.freed_scenes, [])


func test_on_tree_enter_and_on_ready_receive_the_new_scene():
	var seen := []
	await _manager.change_scene(
			SCENE_A,
			_harness.options(
					{
						"on_tree_enter": func(scene): seen.append(["tree_enter", scene]),
						"on_ready": func(scene): seen.append(["ready", scene]),
					}
			),
	)
	var new_scene = _adapter.added_scenes[0]
	assert_eq(seen.size(), 2, "both callbacks should fire once")
	assert_eq(seen[0], ["tree_enter", new_scene])
	assert_eq(seen[1], ["ready", new_scene])


func test_on_tree_enter_can_seed_state_on_the_incoming_scene():
	await _manager.change_scene(
			SCENE_A,
			_harness.options({
						"on_tree_enter": func(scene): scene.marker = 99,
					}),
	)
	assert_eq(_adapter.added_scenes[0].marker, 99)


func test_full_transition_emits_signals_in_order():
	watch_signals(_manager)
	await _manager.change_scene(SCENE_A, _harness.options())
	assert_signal_emitted(_manager, "scene_unloaded")
	assert_signal_emitted(_manager, "transition_finished")
	assert_eq(get_signal_emit_count(_manager, "fade_started"), 2, "one fade out, one fade in")
	assert_eq(get_signal_emit_count(_manager, "fade_complete"), 1)


func test_swap_survives_process_running_mid_swap():
	# _process used to adopt the outgoing scene as _current_scene while _replace_scene was
	# awaiting a frame, re-adding the old scene and orphaning the new one. Skipping the
	# fade-out is what makes the race deterministic: no frames pass before the swap.
	await _manager.change_scene(SCENE_A, _harness.options({ "skip_fade_out": true }))
	assert_eq(_adapter.added_scenes.size(), 1)
	assert_eq(
			_adapter.added_scenes[0].name,
			"SceneA",
			"the incoming scene must be the one installed",
	)
	assert_eq(_manager._current_scene, _adapter.added_scenes[0])


func test_skip_fade_out_only_fades_in():
	watch_signals(_manager)
	await _manager.change_scene(SCENE_A, _harness.options({ "skip_fade_out": true }))
	assert_eq(get_signal_emit_count(_manager, "fade_started"), 1)
	assert_signal_not_emitted(_manager, "fade_complete")


func test_skip_fade_in_leaves_the_screen_covered():
	await _manager.change_scene(SCENE_A, _harness.options({ "skip_fade_in": true }))
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 1.0, 0.001)
	assert_true(_manager.is_transitioning, "still mid-transition with no fade in")
