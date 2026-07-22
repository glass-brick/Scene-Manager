extends GutTest

const Harness = preload("res://tests/helpers/harness.gd")

var _harness
var _manager

func before_each():
	_harness = Harness.new(self, get_tree())
	_manager = _harness.manager

func test_defaults_are_applied_when_nothing_is_passed():
	var options = _manager._get_final_options({})
	assert_eq(options["speed"], 2)
	assert_eq(options["wait_time"], 0.5)
	assert_eq(options["color"], Color("#000000"))

func test_explicit_key_overrides_default():
	var options = _manager._get_final_options({"speed": 7})
	assert_eq(options["speed"], 7)

func test_pattern_expands_to_both_sides():
	var options = _manager._get_final_options({"pattern": "squares"})
	assert_not_null(options["pattern_enter"])
	assert_eq(options["pattern_enter"], options["pattern_leave"])

func test_explicit_pattern_side_wins_over_pattern():
	var options = _manager._get_final_options({
		"pattern": "squares",
		"pattern_leave": "fade",
	})
	assert_not_null(options["pattern_enter"], "pattern_enter falls back to pattern")
	assert_null(options["pattern_leave"], "pattern_leave was explicitly a plain fade")

func test_ease_expands_to_both_sides():
	var options = _manager._get_final_options({"ease": 2.5})
	assert_eq(options["ease_enter"], 2.5)
	assert_eq(options["ease_leave"], 2.5)

func test_explicit_ease_side_wins_over_ease():
	var options = _manager._get_final_options({"ease": 2.5, "ease_leave": 0.5})
	assert_eq(options["ease_enter"], 2.5)
	assert_eq(options["ease_leave"], 0.5)

func test_invert_on_leave_defaults_to_true():
	# Regression: PR #38 made the fade-out inversion configurable.
	var options = _manager._get_final_options({})
	assert_true(options["invert_on_leave"])
	assert_false(options["invert_on_enter"])

func test_callers_dictionary_is_not_mutated():
	var passed := {"speed": 7}
	_manager._get_final_options(passed)
	assert_eq(passed.size(), 1, "options dict gained keys")
	assert_false(passed.has("pattern_enter"))
