// The sound field (sound_field.gd): for each wave a tile of the atlas,
// a field cell 4 px (2 x 2 of the sim's cells), holding how far the
// sound has come to reach that cell along the cave. A cell keeps the
// last corner on its shortest path (x, y in field cells), the path's
// length up to that corner (z, field cells; below 0 not reached yet)
// and the rock the sound crossed on the way (w, field cells). The
// distance at a point is then z + |point - corner|: exact in sight of
// the corner, so rings stay round in open air and bend at the rock's
// corners. One pass takes each cell's best of its eight neighbours:
// kept corner when the neighbour toward that corner shares it (the
// corner is in sight), or the neighbour itself as the new corner.
// Water and rock slow the sound (their costs) and the path inside them
// keeps the neighbour as its corner with the extra cost folded into z.
#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, rgba32f) uniform restrict writeonly image2D dst;
layout(set = 0, binding = 2, r32ui) uniform restrict readonly uimage2D cls;   // The sim's classes per 2 px cell (sim.gd cells)
layout(set = 0, binding = 3, std430) restrict readonly buffer Seeds { vec4 s[]; } seeds;   // Per tile: source x, y (field cells), on, reset

layout(push_constant, std430) uniform Params {
	ivec2 field;      // Field cells of a tile
	int tiles_x;
	int tiles;
	float water_cost;
	float rock_cost;
	int first;        // This frame's first pass: resets apply
	int pad;
} pc;

const vec4 NONE = vec4(0.0, 0.0, -1.0, 0.0);

// 0 open (air, a crumb), 1 water (water, lava, slime), 2 rock.
int kind(uint v) {
	if (v == 0u || (v >= 256u && v < 272u)) {
		return 0;
	}
	if (v == 1u || v == 3u || v == 8u) {
		return 1;
	}
	return 2;
}


void main() {
	ivec2 g = ivec2(gl_GlobalInvocationID.xy);
	ivec2 tc = g / pc.field;
	int tile = tc.y * pc.tiles_x + tc.x;
	if (tc.x >= pc.tiles_x || tile >= pc.tiles) {
		return;
	}
	ivec2 base = tc * pc.field;
	ivec2 l = g - base;
	vec4 sd = seeds.s[tile];
	bool reset = pc.first == 1 && sd.w > 0.5;

	int open_n = 0;
	int wet_n = 0;
	for (int k = 0; k < 4; k++) {
		int c = kind(imageLoad(cls, l * 2 + ivec2(k & 1, k >> 1)).r);
		open_n += c == 0 ? 1 : 0;
		wet_n += c == 1 ? 1 : 0;
	}
	bool open = open_n >= 3;
	bool rock = !open && wet_n < 2;
	float cost = open ? 1.0 : (rock ? pc.rock_cost : pc.water_cost);
	vec2 p = vec2(l) + 0.5;

	vec4 out_v = reset ? NONE : imageLoad(src, g);
	float best = out_v.z < 0.0 ? 1e20 : out_v.z + length(p - out_v.xy);

	if (sd.z > 0.5 && length(p - sd.xy) < 1.5) {
		float d0 = length(p - sd.xy);
		if (d0 < best) {
			best = d0;
			out_v = vec4(sd.xy, 0.0, 0.0);
		}
	}

	if (!reset) {
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				ivec2 nl = l + ivec2(dx, dy);
				if (nl.x < 0 || nl.y < 0 || nl.x >= pc.field.x || nl.y >= pc.field.y) {
					continue;
				}
				vec4 n = imageLoad(src, base + nl);
				if (n.z < 0.0) {
					continue;
				}
				vec2 np = vec2(nl) + 0.5;
				float dn = n.z + length(np - n.xy);
				if (open) {
					// The neighbour's corner kept, if it is in sight: the
					// cell one step from here toward it holds it too.
					vec2 to = n.xy - p;
					float tl = length(to);
					bool seen = tl < 1.5;
					if (!seen) {
						ivec2 q = l + ivec2(round(to / tl * 1.4142));
						q = clamp(q, ivec2(0), pc.field - 1);
						vec4 qv = imageLoad(src, base + q);
						seen = qv.z >= 0.0 && abs(qv.x - n.x) < 0.001 && abs(qv.y - n.y) < 0.001 && abs(qv.z - n.z) < 0.001;
					}
					if (seen) {
						float da = n.z + tl;
						if (da < best - 0.0001) {
							best = da;
							out_v = n;
						}
					}
					// The neighbour as the new corner.
					float db = dn + length(p - np);
					if (db < best - 0.0001) {
						best = db;
						out_v = vec4(np, dn, n.w);
					}
				} else {
					float step_l = length(p - np);
					float db = dn + step_l * cost;
					if (db < best - 0.0001) {
						best = db;
						out_v = vec4(np, dn + step_l * (cost - 1.0), n.w + (rock ? step_l : 0.0));
					}
				}
			}
		}
	}
	imageStore(dst, g, out_v);
}
