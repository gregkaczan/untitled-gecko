// Sound as ripples on the world (waves.gd): drawn over the rock, the
// decor and the light (z 3), under the slugs and the gecko, so only the
// ground moves. Each chew wave is a packet of rings growing from where
// it was made; the hum is an endless train of packets from its source,
// shown while the gecko listens. A ring shifts the world under it along
// its radius, by whole cells when snapped so the pixel art stays crisp,
// lights its crests in its tint and pulls the colours apart a little.
// Along the cave (cave on): the distance and the way the sound travels
// come from the sound field (sound_field.gd), so the rings bend round
// the rock, come out of tunnel mouths and fade behind walls; off, they
// are straight circles that cross rock as if it were air.
shader_type canvas_item;
render_mode unshaded;

const int MAX_WAVES = 16;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float zoom = 2.0;        // Screen px per world px
uniform float cell = 2.0;        // World px of a rock cell
uniform bool snap = true;        // Shifts and ring maths by whole cells
uniform int count = 0;
uniform vec4 waves[MAX_WAVES];   // x, y, age in s, loudness
uniform vec2 hum_at;
uniform float hum_time = 0.0;    // s the hum has played
uniform float hum_show = 0.0;    // 0 to 1: how much of the hum is seen (listening)
// Per kind, chew [0] and hum [1].
uniform float speed[2];          // px/s of the front
uniform float wavelength[2];     // px between rings
uniform float rings[2];          // Rings in a packet
uniform float amp[2];            // px the world shifts at a crest
uniform float reach[2];          // px from the source where the rings die out
uniform float spread[2];         // Ring spacing gained by reach (1: twice as wide there)
uniform float glow[2];           // Crest light
uniform float chroma[2];         // Colour split, of the shift
uniform float period[2];         // s between hum packets (the hum only)
uniform vec3 tint[2];
uniform bool cave = false;
uniform sampler2D field : filter_nearest;   // The field's atlas (sound_field.glsl): corner x, y, length to it, rock crossed, in field cells
uniform float field_cell = 4.0;
uniform ivec2 field_size = ivec2(480, 270);
uniform int tiles_x = 4;
uniform float wave_tile[MAX_WAVES]; // Each chew wave's tile (a float: int arrays do not take a packed array); the hum's is 0
uniform float rock_damp = 24.0;     // px of rock that take a ring down to a third

varying vec2 world;


void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


// The ring height at d px from a source whose front is r px out:
// a packet of rings behind the front, a Hann window over its length,
// fading with distance.
float packet(int k, float d, float r) {
	float lam = wavelength[k] * (1.0 + spread[k] * d / reach[k]);
	float x = r - d;
	float len = max(rings[k], 0.5) * lam;
	if (x < 0.0 || x > len) {
		return 0.0;
	}
	float win = 0.5 - 0.5 * cos(6.2831853 * x / len);
	float fall = clamp(1.0 - d / reach[k], 0.0, 1.0);
	fall *= fall;
	fall *= smoothstep(0.0, lam, d);   // No rip at the source itself
	return sin(6.2831853 * x / lam) * win * fall;
}


// The distance the sound has come to p (px, below 0 not yet), the way
// it travels there and what is left of it after the rock crossed.
vec4 path(vec2 p, vec2 src, int tile) {
	if (!cave) {
		vec2 to = p - src;
		float d = length(to);
		return vec4(d, to / max(d, 0.001), 1.0);
	}
	ivec2 l = clamp(ivec2(floor(p / field_cell)), ivec2(0), field_size - 1);
	vec4 f = texelFetch(field, ivec2(tile % tiles_x, tile / tiles_x) * field_size + l, 0);
	if (f.z < 0.0) {
		return vec4(-1.0, 0.0, 0.0, 0.0);
	}
	vec2 to = p - f.xy * field_cell;
	float tl = length(to);
	return vec4(f.z * field_cell + tl, to / max(tl, 0.001), exp(-f.w * field_cell / rock_damp));
}


void fragment() {
	vec2 p = snap ? (floor(world / cell) + 0.5) * cell : world;
	vec2 shift = vec2(0.0);
	vec3 light_c = vec3(0.0);
	float split = 0.0;
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= count) {
			break;
		}
		vec4 w = waves[i];
		vec4 pa = path(p, w.xy, int(wave_tile[i] + 0.5));
		float h = pa.x < 0.0 ? 0.0 : packet(0, pa.x, w.z * speed[0]) * w.w * pa.w;
		if (h != 0.0) {
			shift += pa.yz * h * amp[0];
			float c = max(h, 0.0) * glow[0];
			light_c += tint[0] * c;
			split += abs(h) * chroma[0];
		}
	}
	if (hum_show > 0.0) {
		vec4 pa = path(p, hum_at, 0);
		float d = max(pa.x, 0.0);
		// The packet the hum's train has at this distance: the train's
		// front is endless, each packet one period of travel behind the last.
		float gap = speed[1] * max(period[1], 0.05);
		float x = hum_time * speed[1] - d;
		float local = x - floor(x / gap) * gap;
		float h = pa.x < 0.0 ? 0.0 : packet(1, d, d + local) * hum_show * pa.w;
		if (h != 0.0) {
			shift += pa.yz * h * amp[1];
			float c = max(h, 0.0) * glow[1];
			light_c += tint[1] * c;
			split += abs(h) * chroma[1];
		}
	}
	vec2 s0 = shift;
	vec2 sr = shift * (1.0 + split);
	vec2 sb = shift * (1.0 - split);
	if (snap) {
		s0 = round(s0 / cell) * cell;
		sr = round(sr / cell) * cell;
		sb = round(sb / cell) * cell;
	}
	// The world under is pulled in from back along the shift: a crest
	// pushes the rock outward.
	vec2 px = SCREEN_PIXEL_SIZE * zoom;
	vec3 col;
	col.r = texture(screen_tex, SCREEN_UV - sr * px).r;
	col.g = texture(screen_tex, SCREEN_UV - s0 * px).g;
	col.b = texture(screen_tex, SCREEN_UV - sb * px).b;
	col += light_c;
	COLOR = vec4(col, 1.0);
}
