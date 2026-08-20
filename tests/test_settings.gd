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

# The options are half settings-derived and half code-only. A new option that lands in neither
# list is one somebody forgot to make configurable, or forgot to decide about.
const CODE_ONLY_OPTIONS := [
	"skip_scene_change",
	"skip_fade_out",
	"skip_fade_in",
	"on_tree_enter",
	"on_ready",
	"on_fade_out",
	"on_fade_in",
]


func test_every_option_is_configurable_or_deliberately_code_only():
	var configurable := []
	for definition in Settings.DEFINITIONS:
		if not definition["key"].is_empty():
			configurable.append(definition["key"])
	for key in _defaults():
		assert_true(
			key in configurable or key in CODE_ONLY_OPTIONS,
			"%s is neither a project setting nor a listed code-only option" % key,
		)


func test_the_code_only_options_survive_being_built_from_settings():
	var defaults := _defaults()
	for key in CODE_ONLY_OPTIONS:
		assert_has(defaults, key)
