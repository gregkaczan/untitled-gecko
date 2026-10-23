// The drawn creatures' layer (critter_layer.gd): its own pixels, a sim
// cell each, and where the cell or its neighbours hold water (the sim's
// cell classes, sim.gd cells_tex, the class in red, water 1) the
// water's hue over them, as render_water.glsl does for the rock and
// metaball.gdshader for the gecko.
shader_type canvas_item;

uniform sampler2D cells_tex : filter_nearest;
uniform bool water_tint = false;
const vec3 WATER_HUE = vec3(0.42, 0.72, 1.0);
const float WATER_K = 0.55;

float wet(vec2 uv) {
	return abs(texture(cells_tex, uv).r * 255.0 - 1.0) < 0.5 ? 1.0 : 0.0;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) {
		discard;
	}
	vec3 col = c.rgb;
	if (water_tint) {
		vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
		float w = wet(UV) + wet(UV + vec2(px.x, 0.0)) + wet(UV - vec2(px.x, 0.0)) + wet(UV + vec2(0.0, px.y)) + wet(UV - vec2(0.0, px.y));
		col = mix(col, col * WATER_HUE, WATER_K * clamp(w / 3.0, 0.0, 1.0));
	}
	COLOR = vec4(col, 1.0);
}
