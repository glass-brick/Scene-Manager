extends RefCounted
## Project Settings backing [member SceneManager.default_options].
##
## The editor plugin calls [method register] to make these show up under
## [code]Project > Project Settings > Scene Manager[/code]; the autoload calls
## [method build_defaults] as it is created. The two never have to agree on anything but the
## [constant DEFINITIONS] table, which is where every default value is written down once.
##
## The [Callable] options are the only ones absent, having nothing Project Settings could show.
## Options that a single transition usually flips rather than a project — the
## [code]skip_*[/code] switches and [code]cache_mode[/code] — are marked advanced, so they sit
## behind the Advanced Settings toggle instead of cluttering the panel.

const PREFIX := "scene_manager/"
const ANIMATION_PLAYER_SETTING := PREFIX + "animation_player"

## One entry per setting. [code]key[/code] is the [member SceneManager.default_options] key it
## feeds, or an empty string for a setting that is not an option.
const DEFINITIONS := [
	{
		"key": "speed",
		"setting": PREFIX + "defaults/speed",
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.1,20,0.1,or_greater",
		"default": 2.0,
	},
	{
		"key": "color",
		"setting": PREFIX + "defaults/color",
		"type": TYPE_COLOR,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": Color("#000000"),
	},
	{
		"key": "pattern",
		"setting": PREFIX + "defaults/pattern",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM_SUGGESTION,
		"hint_string": "fade,circle,curtains,diagonal,horizontal,radial,scribbles,squares,vertical",
		"default": "fade",
	},
	{
		"key": "wait_time",
		"setting": PREFIX + "defaults/wait_time",
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,5,0.05,or_greater",
		"default": 0.5,
	},
	{
		"key": "invert_on_enter",
		"setting": PREFIX + "defaults/invert_on_enter",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": false,
	},
	{
		"key": "invert_on_leave",
		"setting": PREFIX + "defaults/invert_on_leave",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": true,
	},
	{
		"key": "ease",
		"setting": PREFIX + "defaults/ease",
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.1,5,0.1,or_greater",
		"default": 1.0,
	},
	{
		"key": "animation_name",
		"setting": PREFIX + "defaults/animation_name",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": "Fade",
	},
	{
		"key": "background_loading",
		"setting": PREFIX + "defaults/background_loading",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": true,
	},
	{
		"key": "loading_screen",
		"setting": PREFIX + "defaults/loading_screen",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tscn",
		"default": "",
	},
	{
		"key": "min_loading_time",
		"setting": PREFIX + "defaults/min_loading_time",
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,10,0.1,or_greater",
		"default": 0.0,
	},
	{
		"key": "",
		"setting": ANIMATION_PLAYER_SETTING,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tscn",
		"default": "",
	},
	{
		"key": "cache_mode",
		"setting": PREFIX + "defaults/cache_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Ignore:0,Reuse:1,Replace:2,Ignore Deep:3,Replace Deep:4",
		"default": ResourceLoader.CACHE_MODE_IGNORE,
		"advanced": true,
	},
	{
		"key": "skip_scene_change",
		"setting": PREFIX + "defaults/skip_scene_change",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": false,
		"advanced": true,
	},
	{
		"key": "skip_fade_out",
		"setting": PREFIX + "defaults/skip_fade_out",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": false,
		"advanced": true,
	},
	{
		"key": "skip_fade_in",
		"setting": PREFIX + "defaults/skip_fade_in",
		"type": TYPE_BOOL,
		"hint": PROPERTY_HINT_NONE,
		"hint_string": "",
		"default": false,
		"advanced": true,
	},
]


## Declares every setting so the editor shows it with the right widget. Values equal to their
## initial value are not written to [code]project.godot[/code], so this leaves the project file
## untouched until someone actually changes something.
static func register() -> void:
	for definition in DEFINITIONS:
		var setting: String = definition["setting"]
		if not ProjectSettings.has_setting(setting):
			ProjectSettings.set_setting(setting, definition["default"])
		ProjectSettings.set_initial_value(setting, definition["default"])
		ProjectSettings.set_as_basic(setting, !definition.get("advanced", false))
		ProjectSettings.add_property_info(
			{
				"name": setting,
				"type": definition["type"],
				"hint": definition["hint"],
				"hint_string": definition["hint_string"],
			}
		)
	ProjectSettings.save()


## Builds the configurable half of [member SceneManager.default_options] — every option this
## table covers, read from the project and falling back to the shipped default. A project where
## [method register] never ran therefore behaves exactly as the shipped defaults do.
static func build_defaults() -> Dictionary:
	var defaults := { }
	for definition in DEFINITIONS:
		var key: String = definition["key"]
		if key.is_empty():
			continue
		var value = ProjectSettings.get_setting(definition["setting"], definition["default"])
		if key == "loading_screen":
			value = _to_loading_screen(value)
		defaults[key] = value
	defaults.merge(
		{
			"on_tree_enter": func(scene):
				return,
			"on_ready": func(scene):
				return,
			"on_fade_out": func():
				return,
			"on_fade_in": func():
				return,
		}
	)
	return defaults


## Reads the configured custom animation player scene, or an empty string when there is none.
static func get_animation_player_path() -> String:
	return ProjectSettings.get_setting(ANIMATION_PLAYER_SETTING, "")


## The setting is a path, while the option is [code]null[/code], [code]true[/code] or a
## [PackedScene] — an unset path means no loading screen.
static func _to_loading_screen(value):
	if not value is String:
		return value
	if value.is_empty():
		return null
	var scene = load(value)
	assert(scene is PackedScene, "%s is not a PackedScene" % value)
	return scene
