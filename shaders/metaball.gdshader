// Metaball composite for the blob layer. The density texture holds the
// additive sum of soft circle splats. The color texture holds flat
// per-creature colors under the same circles. Pixels above the
// threshold become one smooth body with a dark rim and a lighter core.
shader_type canvas_item;

uniform sampler2D color_tex : filter_nearest;
uniform float threshold = 0.32;
uniform float rim_width = 0.30;
uniform float core_level = 1.7;
uniform float rim_darken = 0.5;
uniform float core_lighten = 0.12;

void fragment() {
	float d = texture(TEXTURE, UV).r;
	if (d < threshold) {
		discard;
	}
	vec3 col = texture(color_tex, UV).rgb;
	float rim = smoothstep(threshold, threshold + rim_width, d);
	col = mix(col * (1.0 - rim_darken), col, step(0.5, rim));
	float core = step(core_level, d);
	col = mix(col, col + vec3(core_lighten), core);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
