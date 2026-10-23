// Metaball composite for the blob layer. The density texture holds the
// additive sum of soft circle splats in red; blue holds flat discs of
// a part lying over the rest of its body (a tail tucked along the
// flank), at the strength of its shade, and green the sum of the
// trunk's splats alone, the part the shade falls on. The color texture
// holds flat per-creature colors under the same circles. Pixels above
// the threshold become one smooth body with a dark rim and a lighter
// core, and the pixel ring just outside the part on top is darkened
// by the strength beside it where it falls inside the trunk's own
// silhouette and off the body's rim: the terminator the merged
// silhouette would not show.
shader_type canvas_item;

uniform sampler2D color_tex : filter_nearest;
uniform float threshold = 0.32;
uniform float rim_width = 0.30;
uniform float core_level = 1.7;
uniform float rim_darken = 0.5;
uniform float core_lighten = 0.12;
uniform float over_darken = 0.3;
// The sim's cell classes (sim.gd cells_tex: the class in red, water 1)
// over the world: a body pixel in the water takes the water's hue, as
// the rock and the creatures in it do (render_water.glsl WATER_HUE).
uniform sampler2D cells_tex : filter_nearest;
uniform bool water_tint = false;
uniform vec2 world_size = vec2(1920.0, 1080.0);
const vec3 WATER_HUE = vec3(0.42, 0.72, 1.0);
const float WATER_K = 0.55;
varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float wet(vec2 p) {
	return abs(texture(cells_tex, p / world_size).r * 255.0 - 1.0) < 0.5 ? 1.0 : 0.0;
}

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
	// beside it, inside the trunk's own silhouette and off the body's
	// rim, darkened by the strongest disc beside it.
	vec2 px = TEXTURE_PIXEL_SIZE;
	float beside = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).b, texture(TEXTURE, UV - vec2(px.x, 0.0)).b),
			max(texture(TEXTURE, UV + vec2(0.0, px.y)).b, texture(TEXTURE, UV - vec2(0.0, px.y)).b));
	float shadow = beside * (1.0 - step(0.002, dens.b)) * step(0.5, rim) * step(threshold, dens.g);
	col = mix(col, col * (1.0 - over_darken), shadow);
	if (water_tint) {
		// The water round the pixel (the body itself is no cell of the
		// sim's: it reads the cells a few px about it).
		float w = wet(world_pos + vec2(3.0, 0.0)) + wet(world_pos - vec2(3.0, 0.0)) + wet(world_pos + vec2(0.0, 3.0)) + wet(world_pos - vec2(0.0, 3.0)) + wet(world_pos);
		col = mix(col, col * WATER_HUE, WATER_K * clamp(w / 3.0, 0.0, 1.0));
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
