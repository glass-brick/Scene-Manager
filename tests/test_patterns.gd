extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")
const CIRCLE_PATH = "res://addons/scene_manager/shader_patterns/circle.png"

var _harness
var _manager


func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager


func test_fade_resolves_to_null():
	assert_null(_manager._load_pattern("fade"))


func test_builtin_name_resolves_to_texture():
	var pattern = _manager._load_pattern("squares")
	assert_true(pattern is Texture, "expected a Texture, got %s" % pattern)


func test_absolute_path_resolves_to_texture():
	var pattern = _manager._load_pattern(CIRCLE_PATH)
	assert_true(pattern is Texture)


func test_texture_is_passed_through_untouched():
	var texture = load(CIRCLE_PATH)
	assert_eq(_manager._load_pattern(texture), texture)


func test_every_shipped_pattern_loads():
	var names = [
		"circle",
		"curtains",
		"diagonal",
		"horizontal",
		"radial",
		"scribbles",
		"squares",
		"vertical",
	]
	for _name in names:
		assert_true(_manager._load_pattern(_name) is Texture, "%s failed to load" % _name)
