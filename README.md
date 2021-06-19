# Godot Scene Manager

![Logo](/logo.png)

This plugin will attempt to solve several common issues with Scene management that we've encountered while developing our games.

![Demonstration of Shader Fades](/scene_manager_demo.gif)

## How to install

1. Open AssetLib in your Godot project, look for Scene Manager, download it and add it to your project
2. Enable the SceneManager plugin from Project Settings -> Plugins

Alternatively, you may download this repo from github and add the `assets` folder to your project, then enable it from your Project Settings

## API

When SceneManager is installed, you will gain access to the `SceneManager` singleton.

## SceneManager

### `func change_scene(path: String, options: Dictionary = defaultOptions) -> void`

This method lets you easily change scenes with transitions. They're highly customizable and we will consider adding progressive loading if it's requested enough. You can pass the following options to this function in a dictionary:

- `type : FadeTypes = FadeTypes.Fade`: Style of the transition. `Fade` is a simple fade-to-black transition, while `ShaderFade` will use a black-and-white image to represent each pixel, allowing for custom transitions.
- `speed : float = 2`: Speed of the moving transition.
- `color : Color = Color('#000000')`: Color to use for the transition screen. It's black by default.
- `wait_time : float = 0.5`: Time spent in the transition screen while switching scenes. Leaving it at 0 with fade will result in the screen not turning black, so it waits a little bit by default.

The Following options are only used when using a `ShaderFade`

- `shader_pattern : (String || Texture) = 'squares'`: Pattern to use for the transition. Using a simple name will load the premade patterns we have designed (you can see them in `addons/scene_manager/shader_patterns`). Otherwise, you may pass an absolute path to your own pattern `"res://my_pattern.png"` or a `Texture` object.
- `shader_pattern_enter : (String || Texture) = null`: Same as `shader_pattern`, but overrides the pattern only for the fade-to-black transition.
- `shader_pattern_leave : (String || Texture) = null`: Same as `shader_pattern`, but overrides the pattern only for the fade-from-black transition.
- `invert_on_leave : Bool = true`: Wether the transition should invert when fading out of black. This usually looks better on, the effect is that the first pixels that turned black are the first ones that fade into the new screen. This generally works for "sweep" transitions like `"horizontal"`, but others such as `"curtains"` might look better with this flag turned off
- `ease : Bool = false`: Wether the animation should "ease" during the transition
- `ease_enter : Bool = null`: Wether the animation should "ease" during the fade-to-black transition
- `ease_leave : Bool = null`: Wether the animation should "ease" during the fade-from-black transition

The following patterns are available out-of-the-box:

- `"circle"`
- `"curtains"`
- `"diagonal"`
- `"horizontal"`
- `"radial"`
- `"scribbles"`
- `"squares"`
- `"vertical"`

### `FadeTypes`

SceneManager defines this enum: `FadeTypes { Fade, ShaderFade }`. It can be accessed via `SceneManager.FadeTypes.Fade`

### Signals

- `scene_unloaded`: emitted when the first scene is unloaded
- `scene_loaded`: emitted when the new scene is loaaded
- `transition_finished`: emitted when the transition finishes
