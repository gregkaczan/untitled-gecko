// Metaball composite for the blob layer. The density texture holds the
// additive sum of soft circle splats in red; blue holds flat discs of
// a part lying over the rest of its body (a tail tucked along the
// flank). The color texture holds flat per-creature colors under the
// same circles. Pixels above the threshold become one smooth body with
// a dark rim and a lighter core, and the pixel ring just outside the
// part on top is darkened where it falls inside the body: the
// terminator the merged silhouette would not show.
shader_type canvas_item;

uniform sampler2D color_tex : filter_nearest;
uniform float threshold = 0.32;
uniform float rim_width = 0.30;
uniform float core_level = 1.7;
uniform float rim_darken = 0.5;
uniform float core_lighten = 0.12;
uniform float over_darken = 0.3;

void fragment() {
	vec4 dens = texture(TEXTURE, UV);
	float d = dens.r;
	if (d < threshold) {
		discard;
	}
	vec3 col = texture(color_tex, UV).rgb;
	float rim = smoothstep(threshold, threshold + rim_width, d);
	col = mix(col * (1.0 - rim_darken), col, step(0.5, rim));
	float core = step(core_level, d);
	col = mix(col, col + vec3(core_lighten), core);
	// The part on top: a pixel just outside its discs with one of them
	// beside it, inside the body and off the body's own rim.
	vec2 px = TEXTURE_PIXEL_SIZE;
	float beside = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).b, texture(TEXTURE, UV - vec2(px.x, 0.0)).b),
			max(texture(TEXTURE, UV + vec2(0.0, px.y)).b, texture(TEXTURE, UV - vec2(0.0, px.y)).b));
	float shadow = step(0.5, beside) * (1.0 - step(0.5, dens.b)) * step(0.5, rim);
	col = mix(col, col * (1.0 - over_darken), shadow);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
