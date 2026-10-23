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
// silhouette would not show. A light version of the slime's bands
// (render_water.glsl) gives the body its form: a pale crescent just
// inside the rim where the body faces the light, up and to the left,
// and a slight shade along the side turned away, the flat color
// between. The way a pixel faces comes from the density's slope, its
// depth from the nearest pixel outside the body.
shader_type canvas_item;

uniform sampler2D color_tex : filter_nearest;
uniform float threshold = 0.32;
uniform float rim_width = 0.30;
uniform float core_level = 1.7;
uniform float rim_darken = 0.5;
uniform float core_lighten = 0.12;
uniform float over_darken = 0.3;
uniform float shade = 0.0;               // 1 draws the bands, 0 the body flat (the default; the debug panel switches it)
uniform vec2 light_dir = vec2(-0.8, -0.6);   // Toward the light, on the screen
uniform vec3 lit_tint = vec3(0.86, 0.90, 0.62);
uniform float lit_mix = 0.5;             // How far the crescent goes toward lit_tint
uniform float lit_width = 2.0;           // Pixels the crescent reaches past the one inside the rim, at its middle
uniform float lit_from = 0.3;            // The crescent covers the rim facing the light by more than this (lower wraps it further round)
uniform float gleam_mix = 0.35;          // A pixel-wide gleam inside the crescent where it faces the light square on
uniform float gleam_from = 0.85;
uniform float shade_darken = 0.22;
uniform float shade_width = 3.0;
uniform float shade_from = 0.2;          // The shade covers the rim facing away by more than this
uniform float core_darken = 0.0;         // The body deeper than core_depth, darker (the slime's dark core)
uniform float core_depth = 5.0;
uniform float smoothness = 0.0;          // 0 hard bands as the slime's, 1 smooth gradients

// Pixels from p to the nearest pixel outside the body, up to 8.
float edge_depth(sampler2D tex, vec2 uv, vec2 px) {
	float best = 8.0;
	for (int y = -7; y <= 7; y++) {
		for (int x = -7; x <= 7; x++) {
			float l = length(vec2(float(x), float(y)));
			if (l >= best) continue;
			if (texture(tex, uv + vec2(float(x), float(y)) * px).r < threshold) best = l;
		}
	}
	return best;
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
	if (shade > 0.0 && rim >= 0.5) {
		// Outward is down the density's slope, taken two pixels wide
		// so it turns smoothly round the body.
		vec2 g = vec2(texture(TEXTURE, UV + vec2(2.0 * px.x, 0.0)).r - texture(TEXTURE, UV - vec2(2.0 * px.x, 0.0)).r,
				texture(TEXTURE, UV + vec2(0.0, 2.0 * px.y)).r - texture(TEXTURE, UV - vec2(0.0, 2.0 * px.y)).r);
		if (dot(g, g) > 1e-6) {
			vec2 out_dir = -normalize(g);
			float depth = edge_depth(TEXTURE, UV, px);
			float lit = dot(out_dir, normalize(light_dir));
			// Each band hard (a step at its reach, as the slime's) or
			// smooth (fading over its reach), mixed by smoothness. The
			// reach is widest where the rim faces the light (or away)
			// square on, tapering off to either side.
			float lit_reach = 2.0 + lit_width * smoothstep(mix(lit_from, 1.0, 0.4), 0.95, lit);
			float lit_hard = step(lit_from, lit) * step(depth, lit_reach);
			float lit_soft = smoothstep(lit_from, 1.0, lit) * (1.0 - smoothstep(1.0, lit_reach + 1.0, depth));
			col = mix(col, lit_tint, lit_mix * shade * mix(lit_hard, lit_soft, smoothness));
			if (lit > gleam_from && depth > 1.5 && depth <= 2.5) {
				col = mix(col, vec3(1.0, 1.0, 0.85), gleam_mix * shade);
			}
			float dark_reach = 2.0 + shade_width * smoothstep(mix(shade_from, 1.0, 0.4), 0.9, -lit);
			float dark_hard = step(shade_from, -lit) * step(depth, dark_reach);
			float dark_soft = smoothstep(shade_from, 1.0, -lit) * (1.0 - smoothstep(1.0, dark_reach + 1.0, depth));
			col *= 1.0 - shade_darken * shade * mix(dark_hard, dark_soft, smoothness);
			float core_hard = step(core_depth, depth);
			float core_soft = smoothstep(core_depth - 2.0, core_depth + 1.0, depth);
			col *= 1.0 - core_darken * shade * mix(core_hard, core_soft, smoothness);
		}
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
