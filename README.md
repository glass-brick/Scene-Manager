# Godot Scene Manager (Godot 4.0 alpha version)

---

## **WARNING** This is lightly tested version. Godot 4.0 is still in alpha, but this version smooths over some of the changes. This documentation has been lightly updated as well.

---

## **WARNING** The Entity Singleton feature is not currently working in this branch.

---

![Logo](/logo.png)

Plugin for managing transitions and Node references between scenes. Expect more features to be added in the future!

![Demonstration of Shader Fades](/scene_manager_demo.gif)

## How to install

1. Open AssetLib in your Godot project, look for Scene Manager, download it and add it to your project
2. Enable the SceneManager plugin from Project Settings -> Plugins

Alternatively, you may download this repo from github and add the `addons` folder to your project, then enable it from your Project Settings~

## How to use

When SceneManager is installed, you will gain access to the `SceneManager` singleton. You can then trigger it's methods directly like so:

```gd
SceneManager.change_scene('res://demo/test.tscn')
```

![Demonstration of Simple Fade](/simple_fade_demo.gif)

There are similar methods for reloading your scene and making a fade without transition, read the [API](#api) docs!

# Update to Godot 4.x guide

With Godot 4.x being so backwards-incompatible, it's unlikely people will have to actually update this library integration rather than starting a new project from scratch.

However, there are some breaking changes in the API that might cause confusion:

- If you used any of these parameters before, remove the `shader` part of their name: `shader_pattern`, `shader_pattern_enter` and `shader_pattern_leave`
- If you used any `ease` parameters as a boolean, replace `true` for `0.5` and `false` for `1.0`
- The `type` parameter no longer has any effect. Please use `"pattern": "fade"` if you want the simple fade transition.
- As an extension of that, we have removed the `FadeTypes` enum. Please remove all references to it.
- The Singleton Entity feature is currently broken. We will try to reimplement it but in the mean time it **WILL** be disabled.

# API

## SceneManager

### `func change_scene(path: String?, options: Dictionary = defaultOptions) -> void`

This method lets you easily change scenes with transitions. They're highly customizable and we will consider adding progressive loading if it's requested enough.

The `path` paremeter accepts an absolute file path for your new scene (i.e: 'res://demo/test.tscn'). If `null` is passed as the path, it will reload the current scene, but for ease-of-use we recommend using the `reload_scene(options)` function explained further down.

You can pass the following options to this function in a dictionary:

- `speed : float = 2`: Speed of the moving transition.
- `color : Color = Color('#000000')`: Color to use for the transition screen. It's black by default.
- `wait_time : float = 0.5`: Time spent in the transition screen while switching scenes. Leaving it at 0 with fade will result in the screen not turning black, so it waits a little bit by default.
- `no_scene_change : Bool = false`: If set to true, it will not change or reload the scene once the fade is complete
- `pattern : (String || Texture) = 'fade'`: Pattern to use for the transition. Using a simple name will load the premade patterns we have designed (you can see them in `addons/scene_manager/shader_patterns`). Otherwise, you may pass an absolute path to your own pattern `"res://my_pattern.png"` or a `Texture` object. You can also specify `'fade'` for a simple fade transition.
- `pattern_enter : (String || Texture) = pattern`: Same as `pattern`, but overrides the pattern only for the fade-to-black transition.
- `pattern_leave : (String || Texture) = pattern`: Same as `pattern`, but overrides the pattern only for the fade-from-black transition.
- `invert_on_leave : Bool = true`: Wether the transition should invert when fading out of black. This usually looks better on, the effect is that the first pixels that turned black are the first ones that fade into the new screen. This generally works for "sweep" transitions like `"horizontal"`, but others such as `"curtains"` might look better with this flag turned off
- `ease : float = 1.0`: Amount of ease the animation should have during the transition.
- `ease_enter : float = ease`: Amount of ease the animation should have during the fade-to-black transition.
- `ease_leave : float = ease`: Amount of ease the animation should have during the fade-from-black transition.

The following patterns are available out-of-the-box:

- `"fade"`
- `"circle"`
- `"curtains"`
- `"diagonal"`
- `"horizontal"`
- `"radial"`
- `"scribbles"`
- `"squares"`
- `"vertical"`

### `func reload_scene(options: Dictionary = defaultOptions) -> void`

This method functions exactly like `change_scene(current_scene_path, options)`, but you do not have to provide the path and it should be slightly faster since it reloads the scene rather than removing it and instantiating again.

Of note, is that this method will not trigger the `scene_unloaded` signal, since nothing is being unloaded. It will however trigger the `scene_loaded` signal. If a legitimate use-case for a `scene_reloaded` signal arises please open an issue and we will change it.

### `func fade_in_place(options: Dictionary = defaultOptions)`

This method functions exactly like `reload_scene({ "no_scene_change": true })`, it will simply trigger the transition used in options, without modifying anything. You can use the `fade_complete` signal if you want to change something while the screen is completely black.

### `is_transitioning: bool`

This variable changes depending of wether a transition is active or not. You can use this to make sure a transition is finished before starting a new one if the `transition_finished` signal does not suit your use-case.

### Signals

- `scene_unloaded`: emitted when the first scene is unloaded
- `scene_loaded`: emitted when the new scene is loaaded
- `fade_complete`: emitted when the fade-to-black animation finishes
- `transition_finished`: emitted when the transition finishes
