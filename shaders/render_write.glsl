// Particle renderer — one thread per particle. Computes material color with
// procedural variation, applies lighting (daylight + drill headlight), handles
// special emissive materials, overlays sonar effect, and writes to the pixel buffer.
// Uses atomicMax for depth-independent compositing: brighter particles always win,
// giving a natural "closest to camera" look without explicit depth sorting.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
const uint O_WD = 6566536u;
const uint O_LD = 7084936u;
const uint O_CD = 7603336u;
const uint O_CT = 8294670u;   // cell class per pixel, read back by the gecko: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_BD = 8813070u;   // bond records: [chunk id, ...] per particle (see sim.gd)
const uint O_EM = 21254670u;   // emission per cell for the light pass (light_seed.glsl): copper and lava glow
const uint BD = 20u;
const uint NB = 8u;
const uint NONE = 0xFFFFFFFFu;
const uint O_SK = 22939598u;   // skinned chunks: [bone + 1, ...] per particle (sim.gd)
const uint O_BC = 25037774u;   // living bonded particles per bone, read back (sim.gd bone_count)
const uint O_SB = 25039822u;   // slime brains [x, y, reach, ...] (sim.gd set_slime)
const uint O_SS = 25039950u;   // per brain [count, sum x, sum y, pad], x and y in 1/16 px
const uint O_SD = 25040014u;   // slime density per cell (render_water.glsl)
// A skinned chunk's colours (critters.gd): stone (mat 4) at fraction
// 0.09 + band * 0.0002: bands 0 to 7 a SKIN_PAL colour, 8 to 15 the same
// glowing; 16 to 31 a decor palette colour (decor_pal) (a shroom drawn from a decor
// sprite), 32 to 47 the same glowing.
const vec3 SKIN_PAL[8] = vec3[8](vec3(0.86, 0.82, 0.70), vec3(0.62, 0.55, 0.44), vec3(0.78, 0.36, 0.30), vec3(0.95, 0.72, 0.42),
                                 vec3(0.42, 0.82, 0.62), vec3(0.20, 0.42, 0.18), vec3(0.34, 0.58, 0.24), vec3(0.62, 0.46, 0.86));
// The decor's palettes by band (decor_palettes.gd, sim.gd O_PL): [count,
// 8 band tops (world px), 8 palette slots, 8 palettes of 16 RGBA8]. A
// decor index is read in the palette of the band its place lies in;
// within BLEND px under a band's top the band above's for a share of the
// cells that shrinks with the depth, a hash a cell, so the seam is a
// dither of two palettes' own colours.
const uint O_PL = 25558414u;
const float BLEND = 32.0;

float band_hash(int cx, int cy) {
    uint h = (uint(cx) * 73856093u) ^ (uint(cy) * 19349663u);
    h = (h ^ (h >> 13u)) * 1274126177u;
    h ^= h >> 16u;
    return float(h & 0xffffu) / 65536.0;
}

vec3 decor_pal(uint idx, float x, float y, float psz) {
    uint n = min(buf.d[O_PL], 8u);
    int cx = int(floor(x / psz)), cy = int(floor(y / psz));
    float yc = (float(cy) + 0.5) * psz;
    uint k = 0u;
    for (uint i = 0u; i < n; i++) {
        if (yc >= uintBitsToFloat(buf.d[O_PL + 1u + i])) k = i;
    }
    if (k > 0u) {
        float t = (yc - uintBitsToFloat(buf.d[O_PL + 1u + k])) / BLEND;
        if (t < 1.0 && band_hash(cx, cy) > t) k -= 1u;
    }
    uint slot = min(buf.d[O_PL + 9u + k], 7u);
    return unpackUnorm4x8(buf.d[O_PL + 17u + slot * 16u + (idx & 15u)]).rgb;
}

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

// Fast integer-style hash: maps any float to a pseudo-random value in [0,1).
// Used for per-particle visual variation so identical materials look natural.
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

// Two-source lighting model: ambient daylight fading with depth + drill headlight.
float compute_light(float px, float py) {
    float ground_y = 324.0; // y-coordinate of the terrain surface
    if (py < ground_y) return 1.0; // above ground = full daylight

    // Daylight penetration: quadratic falloff over ~540 world units below surface.
    // Squaring gives a more natural rapid-then-gradual darkening curve.
    float surface_fade_depth = 270.0 * 2.0;
    float depth_below = py - ground_y;
    float surface_light = clamp(1.0 - depth_below / surface_fade_depth, 0.0, 1.0);
    surface_light *= surface_light; // quadratic falloff for perceptual realism

    // Drill headlight: point light at drill position with quadratic radial falloff
    float dpx = rf(O_P + 9u), dpy = rf(O_P + 10u);   // drill position
    float ddx = rf(O_P + 11u), ddy = rf(O_P + 12u);   // drill facing direction (normalized)
    float dx = px - dpx, dy = py - dpy;                // vector from drill to particle
    float dist = sqrt(dx * dx + dy * dy);
    float light_r = 160.0; // headlight radius in world units
    float drill_light = clamp(1.0 - (dist / light_r) * (dist / light_r), 0.0, 1.0);

    // Directional bias: particles in front of the drill get more light (headlight cone).
    // forward_dot is cosine of angle between drill direction and particle direction,
    // negated because dx/dy point away from drill. Remapped from [-1,1] to [0,1].
    float forward_dot = -(dx * ddx + dy * ddy) / max(dist, 1.0);
    float dir_bias = 0.4 + 0.6 * clamp(forward_dot * 0.5 + 0.5, 0.0, 1.0);
    drill_light *= dir_bias;

    // Take the brighter of the two light sources; floor at 0.04 to avoid pure black
    return clamp(max(surface_light, drill_light), 0.04, 1.0);
}

// A sprite shroom's particle (drawn to its own cell only) also writes
// val, below its own cell's (the caller lowers it), into the cell
// halfway to each particle it is bonded to: where a bend opens a gap
// between neighbours, the gap is filled from inside the sprite, and the
// outline does not grow.
void art_fill(uint id, float px, float py, float psz, uint rw, uint rh, uint off, uint val) {
    int rx = int(floor(px / psz));
    int ry = int(floor(py / psz));
    uint bd = O_BD + id * BD;
    for (uint k = 0u; k < NB; k++) {
        uint j = buf.d[bd + 4u + k * 2u];
        if (j == NONE) continue;
        uint bj = O_PT + j * 8u;
        int cx = int(floor((px + rf(bj)) * 0.5 / psz));
        int cy = int(floor((py + rf(bj + 1u)) * 0.5 / psz));
        if ((cx == rx && cy == ry) || cx < 0 || cx >= int(rw) || cy < 0 || cy >= int(rh)) continue;
        atomicMax(buf.d[off + uint(cy) * rw + uint(cx)], val);
    }
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    uint b = O_PT + id * 8u;
    float px = rf(b), py = rf(b + 1u);        // current position (pos.x, pos.y)
    float mat_f = rf(b + 7u);                 // packed material field
    uint mat = uint(floor(mat_f));             // integer part = material type enum
    float variation = fract(mat_f) * 10.0;     // fractional part scaled to [0,10) for visual variety

    // Map world position to pixel coordinates
    float psz = rf(O_P + 18u); // pixel_size: world units per pixel
    uint rw = uint(rf(O_P + 16u));
    uint rh = uint(rf(O_P + 17u));

    int rx = int(floor(px / psz));
    int ry = int(floor(py / psz));
    if (rx < 0 || rx >= int(rw) || ry < 0 || ry >= int(rh)) return;
    // Static matter (rock and its bands, hard rock, copper, bedrock, the
    // glowshroom and the decor cells) hangs its grain on the cell, not
    // on the particle's slot, fraction or exact position, so a cell
    // painted in the editor, saved and loaded, or filled again, is
    // drawn the same to the pixel. Loose grains and liquids keep their own.
    bool stat = (mat == 3u || mat == 5u || mat == 6u || mat == 7u || mat == 12u);
    float sid = stat ? float(ry * int(rw) + rx) : float(id);
    float svar = stat ? hash11(sid * 0.000731 + 0.37) * 8.9 : variation;
    float sx = stat ? (float(rx) + 0.5) * psz : px;
    float sy = stat ? (float(ry) + 0.5) * psz : py;

    // Light sources among the particles: a copper vein glows a little,
    // lava a lot, a glowshroom (12) green with a slow, shallow breath,
    // each 32 px patch in its own phase. The light pass spreads it
    // from here.
    // A decor cell (mat 12 in a band) glows only in a glow band, in its own colour.
    bool emits = (mat == 6u || mat == 10u);
    vec3 em = (mat == 6u) ? vec3(0.55, 0.28, 0.08) : vec3(1.0, 0.45, 0.10);
    if (mat == 12u) {
        float f = fract(mat_f);
        if (f >= 0.097) { emits = true; em = vec3(0.25, 0.85, 0.35); }
        else {
            uint band = uint(f / 0.003);
            if (band >= 16u) { emits = true; em = decor_pal(band, sx, sy, psz) * 0.9; }
        }
        if (emits) {
            // A slow, shallow breath, a 32 px patch to a phase, so a
            // plant swells as one and the light round it does not flicker.
            float phase = hash11(floor(sx / 32.0) * 7.1 + floor(sy / 32.0) * 13.3) * 6.2832;
            em *= 0.90 + 0.10 * sin(rf(O_P + 36u) * 0.025 + phase);
        }
    }
    bool skin_col = (mat == 4u && fract(mat_f) >= 0.0899);
    uint skin_band = skin_col ? min(uint((fract(mat_f) - 0.09) / 0.0002), 47u) : 0u;
    // A decor sprite's colours are read in the band of its rest place, so
    // a shroom that bends, or a piece of decor fallen, keeps them.
    vec3 skin_c = skin_band >= 16u ? decor_pal(skin_band, rf(O_SK + id * 4u + 2u), rf(O_SK + id * 4u + 3u), psz) : SKIN_PAL[skin_band & 7u];
    if (skin_col && (skin_band & 8u) != 0u && skin_band < 16u) { emits = true; em = skin_c * 0.8; }
    if (skin_col && skin_band >= 32u) { emits = true; em = skin_c * 0.9; }
    if (mat == 14u) { emits = true; em = vec3(0.10, 0.32, 0.08); }
    if (emits) atomicMax(buf.d[O_EM + uint(ry) * rw + uint(rx)], packUnorm4x8(vec4(em, 1.0)));

    // Cell class for the CPU world queries. Solid beats water beats air;
    // fire, smoke, bullets and mites leave no class. Static solid (rock,
    // hard rock, bedrock, copper: anything a yield of 5 or more holds in
    // place, pbd_predict) is 2; a loose grain (sand, clay, the stone of
    // a broken lump) is 4, so the gecko can tell a sand bed from rock
    // and pbd_finalize's rock wall does not freeze a heap. A chunk's
    // cells carry its id, so the CPU can tell a lump from the ground and
    // which lump it is. A lump's lattice turns as it rolls, and a turned
    // lattice leaves cells empty, so each of its particles claims every
    // cell whose centre is within a lattice half-diagonal of it, which
    // closes the gaps at any angle (the colour below does the same).
    uint chunk = (mat < 8u || mat == 12u) ? buf.d[O_BD + id * BD] : 0u;
    {
        uint cls = 0u;
        if (mat == 1u) cls = 1u;
        else if (mat == 10u) cls = 3u;
        else if (mat == 14u) cls = 8u;
        else if (mat < 8u || mat == 12u) {
            float yield_s = (mat < 8u) ? rf(O_M + mat * 12u + 5u) : 8.0;   // 12, the glowshroom, is static
            cls = (chunk != 0u) ? 16u + chunk : ((yield_s >= 5.0) ? 2u : 4u);
            // Rock in its fraction bands (sim.gd frac_of): moss, a slick
            // coat the feet cannot hold (5), thorns that throw the body
            // off (7), and rock that crumbles under a hold (6). All
            // static solid to everything else.
            if (mat == 3u && chunk == 0u) {
                float f = fract(mat_f);
                if (f >= 0.0965) cls = 5u;
                else if (f >= 0.0935) cls = 7u;
                else if (f >= 0.090) cls = 6u;
            }
        }
        if (chunk != 0u) {
            uint sk = buf.d[O_SK + id * 4u];
            if (sk > 0u && sk <= 2048u) atomicAdd(buf.d[O_BC + sk - 1u], 1u);
        }
        // A lump's particle fills the cells round it too, so a turned
        // lump has no holes; a shroom drawn from a sprite (it bends a
        // little, its particles stay a cell apart) only its own, so the
        // art keeps its outline and its spots.
        if (chunk != 0u && !(skin_col && skin_band >= 16u)) {
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    int cx = rx + dx, cy = ry + dy;
                    if (cx < 0 || cx >= int(rw) || cy < 0 || cy >= int(rh)) continue;
                    vec2 cc = vec2((float(cx) + 0.5) * psz, (float(cy) + 0.5) * psz);
                    if (length(vec2(px, py) - cc) < 2.9) atomicMax(buf.d[O_CT + uint(cy) * rw + uint(cx)], cls);
                }
            }
        } else if (cls > 0u) {
            atomicMax(buf.d[O_CT + uint(ry) * rw + uint(rx)], cls);
            if (chunk != 0u) art_fill(id, px, py, psz, rw, rh, O_CT, cls);
        }
    }

    if (mat == 1u) {
        atomicAdd(buf.d[O_WD + uint(ry) * rw + uint(rx)], 1u);
        return;
    }
    if (mat == 14u) {
        // Slime: into its own density (render_water.glsl draws it), and
        // counted to the brain whose reach it is in, so the CPU follows
        // the blob's mass.
        atomicAdd(buf.d[O_SD + uint(ry) * rw + uint(rx)], 1u);
        float best = 1e9;
        uint bi = 16u;
        for (uint i = 0u; i < 16u; i++) {
            uint o = O_SB + i * 8u;
            if (rf(o + 7u) < 0.5) continue;
            float d = length(vec2(px, py) - vec2(rf(o), rf(o + 1u)));
            if (d < rf(o + 2u) && d < best) { best = d; bi = i; }
        }
        if (bi < 16u) {
            atomicAdd(buf.d[O_SS + bi * 4u], 1u);
            atomicAdd(buf.d[O_SS + bi * 4u + 1u], uint(px * 16.0));
            atomicAdd(buf.d[O_SS + bi * 4u + 2u], uint(py * 16.0));
        }
        return;
    }
    if (mat == 10u) {
        atomicAdd(buf.d[O_LD + uint(ry) * rw + uint(rx)], 1u);
        return;
    }
    if (mat == 2u) {
        atomicAdd(buf.d[O_CD + uint(ry) * rw + uint(rx)], 1u);
        return;
    }

    float lighting_on = rf(O_P + 27u);
    float light = (lighting_on > 0.5) ? compute_light(px, py) : 1.0;

    float cr, cg, cb;

    // --- Mite (mat 13): two-particle swarm creature, hot red, self-illuminating ---
    if (mat == 13u) {
        cr = 1.0; cg = 0.3; cb = 0.25;
        uint pixel = uint(ry) * rw + uint(rx);
        atomicMax(buf.d[O_RN + pixel], packUnorm4x8(vec4(cr, cg, cb, 1.0)));
        return;
    }

    // --- Bullet (mat 11): emissive projectile, color by kind (fraction * 100) ---
    if (mat == 11u) {
        uint kind = uint(round(fract(mat_f) * 100.0));
        float glow = hash11(px * 0.3 + py * 0.5 + float(id) * 0.01);
        if (kind == 0u) {            // Rifle: bright white
            cr = 1.0; cg = 1.0; cb = 1.0;
        } else if (kind == 1u) {     // Gatling: light yellow
            cr = 1.0; cg = 0.95; cb = 0.7;
        } else if (kind == 2u) {     // Shotgun: warm amber
            cr = 1.0; cg = 0.75; cb = 0.35;
        } else if (kind == 3u) {     // Rocket: orange-red
            cr = 1.0; cg = 0.35 + glow * 0.15; cb = 0.08 + glow * 0.06;
        } else if (kind == 4u) {     // Cluster shell: olive green
            cr = 0.6; cg = 0.9; cb = 0.3;
        } else if (kind == 5u) {     // Bomblet: lime
            cr = 0.75; cg = 1.0; cb = 0.4;
        } else if (kind == 7u) {     // Singularity round: violet
            cr = 0.7 + glow * 0.2; cg = 0.3; cb = 1.0;
        } else if (kind >= 8u) {     // Enemy spit: acid green
            cr = 0.35; cg = 1.0; cb = 0.45;
        } else {
            cr = 1.0; cg = 1.0; cb = 1.0;
        }
        float shimmer = hash11(px * 0.5 + py * 0.7 + float(id) * 0.003) * 0.1;
        cr += shimmer; cg += shimmer;
        cr = clamp(cr, 0.0, 1.0);
        cg = clamp(cg, 0.0, 1.0);
        cb = clamp(cb, 0.0, 1.0);
        uint pixel = uint(ry) * rw + uint(rx);
        atomicMax(buf.d[O_RN + pixel], packUnorm4x8(vec4(cr, cg, cb, 1.0)));
        return;
    }

    // --- Fire (mat 8): emissive, color ramps from dark ember to bright yellow with life ---
    if (mat == 8u) {
        // life_frac: 1.0=just spawned, 0.0=about to die (frac encodes remaining life, max ~0.099)
        float life_frac = clamp(fract(mat_f) / 0.099, 0.0, 1.0);
        float lf2 = life_frac * life_frac;
        cr = mix(0.25, 1.0, life_frac);          // red: ember→bright
        cg = mix(0.05, 0.78, lf2);               // green ramps slower, boosted for bloom (was 0.65)
        cb = mix(0.0, 0.18, lf2 * life_frac);    // blue barely present, slight boost for hottest core
        // Spatial flicker: hash of position+id gives each fire particle a unique shimmer
        float flicker = hash11(px * 0.17 + py * 0.23 + float(id) * 0.001);
        cr += flicker * 0.15 * life_frac;        // stronger flicker for bloom highlight
        cg += flicker * 0.08 * life_frac;

    // --- Smoke (mat 9): neutral grey wisps that fade as life decreases ---
    } else if (mat == 9u) {
        float life_frac = clamp(fract(mat_f) / 0.099, 0.0, 1.0);
        float base = 0.35 + 0.45 * life_frac;

        float h1 = hash11(float(id) * 0.0059 + 173.7);
        float h2 = hash11(float(id) * 0.0071 + 311.3);

        cr = base;
        cg = base;
        cb = base;

        // Per-particle brightness jitter
        float bright = (h1 - 0.5) * 0.14;
        cr += bright;
        cg += bright;
        cb += bright;

        // Position-dependent noise: smoke color shifts slightly as it drifts
        float pos_h = hash11(px * 0.041 + py * 0.023);
        cr += (pos_h - 0.5) * 0.06;
        cg += (hash11(pos_h * 5.3) - 0.5) * 0.06;
        cb += (hash11(pos_h * 9.1) - 0.5) * 0.06;

        // Wispy highlights: position+id hash creates streaky bright regions
        float wisp = hash11(px * 0.09 + py * 0.15 + float(id) * 0.002) * 0.08 * life_frac;
        cr += wisp;
        cg += wisp * 0.7; // wisps are warm-tinted (less green than red)

    // --- Glowshroom (mat 12): pale green flesh, a lighter cap edge by the hash ---
    } else if (mat == 12u && fract(mat_f) >= 0.097) {
        float h0 = hash11(svar * 127.1 + sid * 0.0013);
        float h1 = hash11(svar * 269.5 + sid * 0.0029);
        cr = 0.42 + (h0 - 0.5) * 0.12;
        cg = 0.82 + (h1 - 0.5) * 0.12;
        cb = 0.46 + (h0 - 0.5) * 0.10;
        float speck = step(0.85, hash11(svar * 53.3 + sid * 0.009)) * 0.15;
        cr += speck; cg += speck; cb += speck;

    // --- Decor (mat 12 in a band): a stamp's pixel in its palette colour, a touch of jitter ---
    } else if (mat == 12u) {
        vec3 c = decor_pal(uint(fract(mat_f) / 0.003), sx, sy, psz);
        float j = (hash11(svar * 127.1 + sid * 0.0013) - 0.5) * 0.04;
        cr = c.r + j; cg = c.g + j; cb = c.b + j;

    // --- Standard materials (sand, clay, rock, stone, hard rock, copper, bedrock) ---
    // (lava mat 10 redirected to density buffer above, composited by render_water)
    } else {
        // Base color from material property table
        cr = rf(O_M + mat * 12u + 6u);
        cg = rf(O_M + mat * 12u + 7u);
        cb = rf(O_M + mat * 12u + 8u);
        // A skinned chunk (a shroom, a vine) in its palette colour. Rock
        // in its bands: moss (a dark wet green), thorns (pale, bony)
        // and crumbling rock (paler, dry).
        if (skin_col) { cr = skin_c.r; cg = skin_c.g; cb = skin_c.b; }
        if (mat == 3u) {
            float f = fract(mat_f);
            if (f >= 0.0965) { cr = 0.20; cg = 0.42; cb = 0.20; }
            else if (f >= 0.0935) { cr = 0.80; cg = 0.82; cb = 0.78; }
            else if (f >= 0.090) { cr = 0.46; cg = 0.40; cb = 0.33; }
        }

        // Per-particle color variation: 3 independent hashes give RGB jitter.
        // Uses variation (from fractional material) + particle ID for stable
        // uniqueness; static matter the cell's stand-ins (sid, svar above).
        float h0 = hash11(svar * 127.1 + sid * 0.0013);
        float h1 = hash11(svar * 269.5 + sid * 0.0029);
        float h2 = hash11(svar * 419.2 + sid * 0.0047);
        // Stone (mat 4) varies less: a lump reads as one pale thing
        // against the ground's grain. Hard rock (5) and bedrock (7) are
        // smoother still, so a seam of either reads as one slab.
        // A shroom drawn from a decor sprite (skin bands 16 and up) keeps
        // the art's colours: no grain of its own, a touch of the speckle.
        bool art = skin_col && skin_band >= 16u;
        float var_strength = art ? 0.0 : ((mat == 4u) ? 0.07 : ((mat == 5u) ? 0.10 : ((mat == 7u) ? 0.04 : 0.22)));
        cr += (h0 - 0.5) * var_strength;
        cg += (h1 - 0.5) * var_strength;
        cb += (h2 - 0.5) * var_strength;

        // Position-dependent noise: prevents banding when many same-material particles cluster
        // (a skinned chunk's particle by its rest place, so a bending
        // stem keeps its speckle instead of shimmering)
        float nsx = skin_col ? rf(O_SK + id * 4u + 2u) : sx;
        float nsy = skin_col ? rf(O_SK + id * 4u + 3u) : sy;
        float pos_hash = hash11(nsx * 0.031 + nsy * 0.017);
        float pos_k = art ? 0.02 : 0.08;
        cr += (pos_hash - 0.5) * pos_k;
        cg += (hash11(pos_hash * 3.7) - 0.5) * pos_k;
        cb += (hash11(pos_hash * 7.3) - 0.5) * pos_k;

        // Water: extra blue shimmer for translucent look
        if (mat == 1u) {
            float shimmer = hash11(px * 0.07 + py * 0.13 + variation) * 0.1;
            cb += 0.08 + shimmer;
            cg += 0.03;
        }

        // Hard rock: a few pale flecks, so it reads as a different stone
        // from the plain rock round it, not just a darker patch of it.
        if (mat == 5u) {
            float fleck = step(0.94, hash11(svar * 41.7 + sid * 0.007)) * 0.14;
            cr += fleck; cg += fleck; cb += fleck * 1.1;
        }
        // Copper: warm patina with orange-tinted glints (18% chance)
        if (mat == 6u) {
            float patina = hash11(sx * 0.11 + sy * 0.17 + svar);
            cr += patina * 0.12;
            cg += patina * 0.06;
            float glint = step(0.82, hash11(svar * 53.3 + sid * 0.009)) * 0.25;
            cr += glint; cg += glint * 0.7; // warm glint (less green)
        }
        // Bedrock: faint level banding, a slab laid down in sheets.
        if (mat == 7u) {
            float band = sin(sy * 0.11 + hash11(floor(sy / 24.0)) * 3.0) * 0.025;
            cr += band; cg += band; cb += band * 1.3;
        }

        // Depth gradient: particles lower in the world are subtly darker (up to 20%)
        float depth = 1.0 - (sy / rf(O_P + 3u)) * 0.2;
        cr *= depth;
        cg *= depth;
        cb *= depth;
    }

    // Ores and lava emit their own light so they're visible even in darkness
    float ore_glow = 0.0;
    if (mat == 6u) ore_glow = 0.10;  // copper: faint glow
    // mat 10 (lava) redirected to density buffer above; rendered by render_water
    if (mat == 12u) ore_glow = 0.3;  // glowshroom: it is a lamp

    float final_light = min(light + ore_glow, 1.0);

    if (mat < 8u || mat == 12u) {
        cr *= final_light;
        cg *= final_light;
        cb *= final_light;
    }

    // --- Sonar overlay: expanding ring that reveals ore deposits through terrain ---
    float sonar_on = rf(O_P + 30u);
    float sonar_r = rf(O_P + 31u);   // current ring radius (expands over time)
    float sonar_cx = rf(O_P + 32u);
    float sonar_cy = rf(O_P + 33u);

    if (sonar_on > 0.5 && sonar_r > 1.0) {
        float sdx = px - sonar_cx, sdy = py - sonar_cy;
        float sdist = sqrt(sdx * sdx + sdy * sdy);
        float max_r = 300.0; // maximum sonar range

        // Ore reveal: ores behind the expanding wavefront glow in material-specific colors
        bool is_ore = (mat >= 5u && mat <= 7u);
        if (is_ore && sdist < sonar_r) {
            // "behind" = how far the ring has passed this particle (normalized).
            // Reveal fades quickly so only ores near the ring edge are highlighted.
            float behind = (sonar_r - sdist) / max_r;
            float reveal = clamp(1.0 - behind * 2.5, 0.0, 1.0);
            reveal *= reveal; // squared for sharper falloff

            // Per-ore-type sonar highlight colors
            float sr = 0.0, sg = 0.0, sb = 0.0;
            if (mat == 5u) { sr = 0.3; sg = 0.6; sb = 1.0; }  // iron: blue
            if (mat == 6u) { sr = 1.0; sg = 0.6; sb = 0.15; } // copper: orange
            if (mat == 7u) { sr = 1.0; sg = 0.92; sb = 0.2; } // gold: yellow

            // Sinusoidal pulse on the glow creates a radar-sweep shimmer effect
            float pulse = 0.8 + 0.2 * sin(sdist * 0.15 + sonar_r * 0.1);
            float glow = reveal * 0.85 * pulse;
            cr = mix(cr, sr, glow);
            cg = mix(cg, sg, glow);
            cb = mix(cb, sb, glow);
        }

        // Visible ring edge: teal-colored band at the sonar wavefront, fading with distance
        float ring_dist = abs(sdist - sonar_r);
        if (ring_dist < 6.0 && mat < 8u) { // only on solid materials, not fire/smoke
            float ring_alpha = (1.0 - ring_dist / 6.0); // fade across 6-unit ring thickness
            ring_alpha *= (1.0 - sonar_r / max_r);       // ring fades as it expands to max range
            cr = mix(cr, 0.2, ring_alpha * 0.4);
            cg = mix(cg, 0.9, ring_alpha * 0.4);
            cb = mix(cb, 0.7, ring_alpha * 0.4);
        }
    }

    cr = clamp(cr, 0.0, 1.0);
    cg = clamp(cg, 0.0, 1.0);
    cb = clamp(cb, 0.0, 1.0);

    // Write to pixel buffer using atomicMax: packUnorm4x8 packs RGBA into a uint where
    // brighter colors produce higher uint values, so atomicMax naturally composites
    // the brightest (most visible) particle at each pixel — no depth buffer needed.
    uint packed = packUnorm4x8(vec4(cr, cg, cb, 1.0));
    if (chunk != 0u && !(skin_col && skin_band >= 16u)) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int cx = rx + dx, cy = ry + dy;
                if (cx < 0 || cx >= int(rw) || cy < 0 || cy >= int(rh)) continue;
                vec2 cc = vec2((float(cx) + 0.5) * psz, (float(cy) + 0.5) * psz);
                if (length(vec2(px, py) - cc) < 2.9) atomicMax(buf.d[O_RN + uint(cy) * rw + uint(cx)], packed);
            }
        }
        return;
    }
    uint pixel = uint(ry) * rw + uint(rx);
    atomicMax(buf.d[O_RN + pixel], packed);
    if (chunk != 0u) art_fill(id, px, py, psz, rw, rh, O_RN, packUnorm4x8(vec4(cr, cg, cb, 254.0 / 255.0)));
}
