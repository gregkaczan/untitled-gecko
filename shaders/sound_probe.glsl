// The sound field read at the creatures' ears (sound_field.gd): per ear
// and tile the corner to head for (world px), the distance the sound
// travels to the ear (px, below 0 not reached) and the rock it crossed
// (px), read back for the hearing (waves.gd tick).
#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D field;
layout(set = 0, binding = 1, std430) restrict readonly buffer Ears { vec2 e[]; } ears;   // World px
layout(set = 0, binding = 2, std430) restrict writeonly buffer Heard { vec4 h[]; } heard;

layout(push_constant, std430) uniform Params {
	ivec2 field;
	int tiles_x;
	int tiles;
	int ears;
	float cell;       // World px of a field cell
	int pad0;
	int pad1;
} pc;


void main() {
	int i = int(gl_GlobalInvocationID.x);
	if (i >= pc.ears * pc.tiles) {
		return;
	}
	int ear = i / pc.tiles;
	int tile = i - ear * pc.tiles;
	vec2 p = ears.e[ear] / pc.cell;
	ivec2 l = clamp(ivec2(floor(p)), ivec2(0), pc.field - 1);
	ivec2 base = ivec2(tile % pc.tiles_x, tile / pc.tiles_x) * pc.field;
	vec4 f = imageLoad(field, base + l);
	if (f.z < 0.0) {
		heard.h[i] = vec4(0.0, 0.0, -1.0, 0.0);
		return;
	}
	heard.h[i] = vec4(f.xy * pc.cell, (f.z + length(p - f.xy)) * pc.cell, f.w * pc.cell);
}
