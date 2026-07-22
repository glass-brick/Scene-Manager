extends Control

# The manager frees its loading screen before the transition ends, so the instance is gone
# by the time a test can inspect it. Record what happened statically instead.
static var instantiated_count := 0
static var removed_count := 0
static var progress_reports := []

static func reset() -> void:
	instantiated_count = 0
	removed_count = 0
	progress_reports = []

func _init() -> void:
	instantiated_count += 1

func _exit_tree() -> void:
	removed_count += 1

func set_progress(value: float) -> void:
	progress_reports.append(value)
