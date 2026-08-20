extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const Settings = preload("res://addons/scene_manager/SceneManagerSettings.gd")

var _touched := []


func after_each():
	# ProjectSettings is global state; setting a value back to null removes the entry.
	for setting in _touched:
		ProjectSettings.set_setting(setting, null)
	_touched.clear()
	await wait_process_frames(1)


func _configure(setting: String, value) -> void:
	_touched.append(setting)
	ProjectSettings.set_setting(setting, value)


func _defaults() -> Dictionary:
	return Harness.new(self, get_tree()).manager.default_options


func test_unset_settings_keep_the_shipped_defaults():
	var defaults := _defaults()
	assert_eq(defaults["speed"], 2.0)
	assert_eq(defaults["color"], Color("#000000"))
	assert_eq(defaults["animation_name"], "Fade")


func test_defaults_come_from_project_settings():
	_configure("scene_manager/defaults/speed", 7.0)
	_configure("scene_manager/defaults/wait_time", 1.25)
	_configure("scene_manager/defaults/color", Color("#ff0000"))
	_configure("scene_manager/defaults/pattern", "squares")
	var defaults := _defaults()
	assert_eq(defaults["speed"], 7.0)
	assert_eq(defaults["wait_time"], 1.25)
	assert_eq(defaults["color"], Color("#ff0000"))
	assert_eq(defaults["pattern"], "squares")


func test_a_configured_default_reaches_a_transition():
	_configure("scene_manager/defaults/color", Color("#00ff00"))
	var harness = Harness.new(self, get_tree())
	await harness.manager.fade_out({ "speed": 50, "wait_time": 0.0 })
	assert_eq(harness.manager._shader_blend_rect.material.get_shader_parameter("fade_color"), Color("#00ff00"))
	await wait_process_frames(1)


func test_a_loading_screen_path_becomes_a_packed_scene():
	_configure("scene_manager/defaults/loading_screen", "res://tests/fixtures/loading_screen.tscn")
	assert_true(_defaults()["loading_screen"] is PackedScene)


func test_an_empty_loading_screen_path_means_none():
	_configure("scene_manager/defaults/loading_screen", "")
	assert_null(_defaults()["loading_screen"])


func test_the_animation_player_setting_installs_the_player():
	_configure(
		"scene_manager/animation_player",
		"res://tests/fixtures/custom_animation_player.tscn",
	)
	var harness = Harness.new(self, get_tree())
	assert_true(harness.manager._user_animation_player is AnimationPlayer)


func test_every_setting_maps_to_a_real_option():
	var defaults := _defaults()
	for definition in Settings.DEFINITIONS:
		var key: String = definition["key"]
		if key.is_empty():
			continue
		assert_has(defaults, key, definition["setting"])


func test_setting_defaults_match_the_shipped_option_defaults():
	var defaults := _defaults()
	for definition in Settings.DEFINITIONS:
		var key: String = definition["key"]
		# loading_screen is a path in the settings and a PackedScene in the options.
		if key.is_empty() or key == "loading_screen":
			continue
		assert_eq(defaults[key], definition["default"], definition["setting"])
