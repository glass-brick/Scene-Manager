shader_type canvas_item;

uniform sampler2D dissolve_texture;
uniform float dissolve_amount : hint_range(0, 1);
uniform vec3 fade_color;
uniform bool inverted;

void fragment() {
	if (dissolve_amount == 0.0 || dissolve_amount == 1.0) {
		COLOR = vec4(fade_color.rgb, dissolve_amount);
	} else {
		float sample = texture(dissolve_texture, UV).r;
		if (inverted) {
			sample = 1.0 - sample;
		}
		COLOR = vec4(fade_color.rgb, step(sample, dissolve_amount));
	}
}