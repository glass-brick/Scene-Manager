extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const PLAYER_PATH := "res://tests/fixtures/custom_animation_player.tscn"
const PlayerScene = preload(PLAYER_PATH)
const PartialPlayerScene = preload("res://tests/fixtures/partial_animation_player.tscn")

var _harness
var _manager


func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager


func after_each():
	# A finished transition resumes inside AnimationPlayer's animation_finished emission;
	# let that unwind before GUT frees the manager out from under it.
	await wait_process_frames(1)


func test_set_animation_player_accepts_a_path():
	_manager.set_animation_player(PLAYER_PATH)
	assert_true(_manager._user_animation_player is AnimationPlayer)
	assert_eq(
		_manager._user_animation_player.get_parent(),
		_manager.get_node("CanvasLayer"),
		"the custom player renders on the fade layer, above the game",
	)


func test_set_animation_player_accepts_a_packed_scene():
	_manager.set_animation_player(PlayerScene)
	assert_true(_manager._user_animation_player.has_animation("Fade"))


func test_a_custom_fade_animation_takes_over_by_default():
	_manager.set_animation_player(PlayerScene)
	await _manager.fade_out(_harness.options())
	assert_eq(_manager._user_animation_player.assigned_animation, "Fade")
	assert_eq(_manager._animation_player.assigned_animation, "", "built-in player stays idle")


func test_a_player_without_the_animation_falls_back_to_the_builtin_fade():
	_manager.set_animation_player(PartialPlayerScene)
	await _manager.fade_out(_harness.options())
	assert_eq(_manager._animation_player.assigned_animation, "Fade")
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 1.0, 0.001)


func test_a_named_animation_is_opt_in_per_side():
	_manager.set_animation_player(PartialPlayerScene)
	await _manager.fade_out(_harness.options({ "animation_name_enter": "roll" }))
	assert_eq(_manager._user_animation_player.assigned_animation, "roll")
	assert_eq(_manager._animation_player.assigned_animation, "")


func test_a_null_animation_name_forces_the_builtin_fade():
	_manager.set_animation_player(PlayerScene)
	await _manager.fade_out(_harness.options({ "animation_name": null }))
	assert_eq(_manager._animation_player.assigned_animation, "Fade")
	assert_ne(
		_manager._user_animation_player.assigned_animation,
		"Fade",
		"the custom player was not asked to animate",
	)


func test_speed_drives_the_custom_players_speed_scale():
	_manager.set_animation_player(PlayerScene)
	await _manager.fade_out(_harness.options({ "speed": 50 }))
	assert_eq(_manager._user_animation_player.speed_scale, 50.0)


func test_a_custom_fade_out_is_reset_when_the_builtin_fades_back_in():
	_manager.set_animation_player(PartialPlayerScene)
	await _manager.fade_out(_harness.options({ "animation_name_enter": "roll" }))
	await _manager.fade_in(_harness.options({ "pattern_leave": "squares" }))
	assert_eq(
		_manager._user_animation_player.assigned_animation,
		"RESET",
		"the custom visuals are cut away so the built-in fade can reveal",
	)
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 0.0, 0.001)


func test_a_builtin_fade_out_is_cleared_when_a_custom_animation_fades_back_in():
	_manager.set_animation_player(PartialPlayerScene)
	await _manager.fade_out(_harness.options({ "pattern_enter": "squares" }))
	assert_almost_eq(_harness.shader_param("dissolve_amount"), 1.0, 0.001, "screen is covered")
	await _manager.fade_in(_harness.options({ "animation_name_leave": "roll" }))
	assert_eq(_manager._user_animation_player.assigned_animation, "roll")
	assert_almost_eq(
		_harness.shader_param("dissolve_amount"),
		0.0,
		0.001,
		"the shader overlay is cut away so the custom animation can reveal",
	)


func test_setting_a_second_player_frees_the_first():
	_manager.set_animation_player(PlayerScene)
	var first = _manager._user_animation_player
	_manager.set_animation_player(PartialPlayerScene)
	await wait_process_frames(1)
	assert_false(is_instance_valid(first), "the replaced player is freed")
	assert_false(_manager._user_animation_player.has_animation("Fade"))


func test_setting_null_reverts_to_the_builtin_fade():
	_manager.set_animation_player(PlayerScene)
	_manager.set_animation_player(null)
	await _manager.fade_out(_harness.options())
	assert_null(_manager._user_animation_player)
	assert_eq(_manager._animation_player.assigned_animation, "Fade")
