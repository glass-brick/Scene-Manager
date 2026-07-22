extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")

var _harness
var _manager

func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager

func after_each():
	# A finished transition resumes inside AnimationPlayer's animation_finished emission;
	# let that unwind before GUT frees the manager out from under it.
	await wait_process_frames(1)

func test_fade_out_uses_pattern_enter_as_dissolve_texture():
	await _manager.fade_out(_harness.options({"pattern": "squares"}))
	assert_not_null(_harness.shader_param("dissolve_texture"))
	assert_false(_harness.shader_param("fade"), "a pattern means this is not a flat fade")

func test_plain_fade_sets_the_fade_flag_and_no_texture():
	await _manager.fade_out(_harness.options({"pattern": "fade"}))
	assert_null(_harness.shader_param("dissolve_texture"))
	assert_true(_harness.shader_param("fade"))

func test_fade_out_applies_color_and_inversion():
	await _manager.fade_out(_harness.options({
		"color": Color("#ff0000"),
		"invert_on_enter": true,
	}))
	assert_eq(_harness.shader_param("fade_color"), Color("#ff0000"))
	assert_true(_harness.shader_param("inverted"))

func test_fade_in_uses_invert_on_leave():
	# Regression: PR #38 — fade-in inverts by default so the reveal mirrors the cover.
	await _manager.fade_in(_harness.options({"pattern": "squares"}))
	assert_true(_harness.shader_param("inverted"))

func test_fade_in_honours_explicit_invert_on_leave():
	await _manager.fade_in(_harness.options({"pattern": "squares", "invert_on_leave": false}))
	assert_false(_harness.shader_param("inverted"))

func test_speed_option_drives_animation_speed_scale():
	await _manager.fade_out(_harness.options({"speed": 50}))
	assert_eq(_manager._animation_player.speed_scale, 50)

func test_ease_is_written_to_the_animation_track():
	await _manager.fade_out(_harness.options({"ease_enter": 2.5}))
	var animation = _manager._animation_player.get_animation("ShaderFade")
	assert_almost_eq(animation.track_get_key_transition(0, 0), 2.5, 0.001)

func test_fade_out_covers_the_screen_and_fade_in_clears_it():
	await _manager.fade_out(_harness.options())
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 1.0, 0.001, "screen should be covered")
	await _manager.fade_in(_harness.options())
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 0.0, 0.001, "screen should be clear")

func test_fade_out_emits_started_then_complete():
	watch_signals(_manager)
	await _manager.fade_out(_harness.options())
	assert_signal_emitted(_manager, "fade_started")
	assert_signal_emitted(_manager, "fade_complete")

func test_is_transitioning_is_true_during_the_transition():
	assert_false(_manager.is_transitioning, "starts idle")
	await _manager.fade_out(_harness.options())
	assert_true(_manager.is_transitioning, "still covered after fading out")
	await _manager.fade_in(_harness.options())
	assert_false(_manager.is_transitioning, "idle again once revealed")

func test_fade_callbacks_are_invoked():
	var calls := []
	await _manager.fade_out(_harness.options({"on_fade_out": func(): calls.append("out")}))
	await _manager.fade_in(_harness.options({"on_fade_in": func(): calls.append("in")}))
	assert_eq(calls, ["out", "in"])
