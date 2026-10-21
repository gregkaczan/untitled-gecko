// Light seed: the start of this tick's light, per cell. Last tick's
// light decayed (so a glow that moves on leaves a short trail and
// nothing else), the emission the particles wrote (copper, lava),
// daylight on the open cells of the exit's rect, and the glows (the
// gecko's, a slug's, the level's lights: points, strips and cones)
// within their radius. light_spread.glsl then
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
const uint O_LP = 22291470u;   // light parameters (sim.gd): [0] decay of last tick's light, [1] glow count, [4..7] daylight rect x0 y0 x1 y1, [8..10] daylight colour, [11..14] passage of air, water, loose grains, solid; from [16] the glows, 8 floats each: x y r g b radius x2 y2 (a strip to x2 y2, a cone when the radius is negative)

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
    // The glows, 8 floats each: x y r g b radius x2 y2. A point when the
    // ends match, else a strip of light along the segment; a negative
    // radius makes a cone from the source (x, y) to the aim (x2, y2),
    // two cells wide at the source and the radius wide at the aim,
    // fading toward it, the spread carrying it on from there.
    uint n = min(uint(rf(O_LP + 1u)), 10u);
    for (uint i = 0u; i < n; i++) {
        uint s = O_LP + 16u + i * 8u;
        float rad = rf(s + 5u);
        vec2 a = vec2(rf(s), rf(s + 1u));
        vec2 b = vec2(rf(s + 6u), rf(s + 7u));
        vec3 col = vec3(rf(s + 2u), rf(s + 3u), rf(s + 4u));
        vec2 ab = b - a;
        float len2 = dot(ab, ab);
        if (rad > 0.0) {
            float t = len2 > 0.0 ? clamp(dot(c - a, ab) / len2, 0.0, 1.0) : 0.0;
            float dist = length(c - (a + ab * t));
            if (dist < rad) l = max(l, col * (1.0 - 0.5 * dist / rad));
        } else if (len2 > 0.0) {
            float spread = -rad;
            float len = sqrt(len2);
            float t = dot(c - a, ab) / len2;
            if (t >= 0.0 && t <= 1.0) {
                float perp = abs((c.x - a.x) * ab.y - (c.y - a.y) * ab.x) / len;
                float limit = mix(2.0 * psz, spread, t);
                if (perp < limit) l = max(l, col * (1.0 - 0.5 * perp / limit) * (1.0 - 0.6 * t));
            }
        }
    }
    put(O_LB, id, l);
}
