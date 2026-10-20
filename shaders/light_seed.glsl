// Light seed: the start of this tick's light, per cell. Last tick's
// light decayed (so a glow that moves on leaves a short trail and
// nothing else), the emission the particles wrote (copper, lava),
// daylight on the open cells of the exit's rect, and the glows (the
// gecko's, a slug's) within their radius. light_spread.glsl then
// carries it from cell to cell. Written into the B half; the spread's
// first pass reads it from there.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u;
const uint O_CT = 8294670u;   // cell class per pixel: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_LA = 19181070u;   // light, two uints per cell (RG and B as 16-bit): the result of the last tick's spread, and of this one
const uint O_LB = 20217870u;   // light, the spread's other half
const uint O_EM = 21254670u;   // emission per cell, packed RGB8, written by the particles (render_write.glsl)
const uint O_LO = 21773070u;   // the light as RGB8 per cell, for the overlay texture (light_out.glsl, read back by sim.gd)
const uint O_LP = 22291470u;   // light parameters (sim.gd): [0] decay of last tick's light, [1] glow count, [4..7] daylight rect x0 y0 x1 y1, [8..10] daylight colour, [11..14] passage of air, water, loose grains, solid; from [16] the glows, 6 floats each: x y r g b radius

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

// 16 bits a channel: with 8 the small loss per cell rounded away at low
// levels and the light stuck there instead of fading out.
vec3 at(uint base, uint i) {
    uint b = base + i * 2u;
    return vec3(unpackUnorm2x16(buf.d[b]), unpackUnorm2x16(buf.d[b + 1u]).x);
}

void put(uint base, uint i, vec3 l) {
    uint b = base + i * 2u;
    buf.d[b] = packUnorm2x16(l.rg);
    buf.d[b + 1u] = packUnorm2x16(vec2(l.b, 1.0));
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u)), rh = uint(rf(O_P + 17u));
    if (id >= rw * rh) return;
    float psz = rf(O_P + 18u);
    vec2 c = (vec2(float(id % rw), float(id / rw)) + 0.5) * psz;
    uint cls = buf.d[O_CT + id];
    vec3 l = at(O_LA, id) * rf(O_LP);
    l = max(l, unpackUnorm4x8(buf.d[O_EM + id]).rgb);
    bool open = (cls == 0u || cls == 1u || cls == 3u);
    if (open && c.x >= rf(O_LP + 4u) && c.x < rf(O_LP + 6u) && c.y >= rf(O_LP + 5u) && c.y < rf(O_LP + 7u)) {
        l = max(l, vec3(rf(O_LP + 8u), rf(O_LP + 9u), rf(O_LP + 10u)));
    }
    uint n = min(uint(rf(O_LP + 1u)), 13u);
    for (uint i = 0u; i < n; i++) {
        uint s = O_LP + 16u + i * 6u;
        float rad = rf(s + 5u);
        float dist = length(c - vec2(rf(s), rf(s + 1u)));
        if (dist < rad) {
            l = max(l, vec3(rf(s + 2u), rf(s + 3u), rf(s + 4u)) * (1.0 - 0.5 * dist / rad));
        }
    }
    put(O_LB, id, l);
}
