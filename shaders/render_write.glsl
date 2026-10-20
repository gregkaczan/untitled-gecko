// Particle renderer — one thread per particle. Computes material color with
// procedural variation, applies lighting (daylight + drill headlight), handles
// special emissive materials, overlays sonar effect, and writes to the pixel buffer.
// Uses atomicMax for depth-independent compositing: brighter particles always win,
// giving a natural "closest to camera" look without explicit depth sorting.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 160u, GH = 90u, MPC = 32u, PC = 129600u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 14536u, O_PT = 475336u, O_RN = 1512136u;
const uint O_WD = 1641736u;
const uint O_LD = 1771336u;
const uint O_CD = 1900936u;
const uint O_CT = 2073870u;   // cell class per pixel, read back by the gecko: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_BD = 2203470u;   // bond records: [chunk id, ...] per particle (see sim.gd)
const uint BD = 20u;

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
        else if (mat < 8u || mat == 12u) {
            float yield_s = (mat < 8u) ? rf(O_M + mat * 12u + 5u) : 2.0;
            cls = (chunk != 0u) ? 16u + chunk : ((yield_s >= 5.0) ? 2u : 4u);
        }
        if (chunk != 0u) {
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
        }
    }

    if (mat == 1u) {
        atomicAdd(buf.d[O_WD + uint(ry) * rw + uint(rx)], 1u);
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

    // --- Purple ore (mat 12): self-illuminating purple crystal ---
    if (mat == 12u) {
        float h0 = hash11(variation * 127.1 + float(id) * 0.0013);
        float h1 = hash11(variation * 269.5 + float(id) * 0.0029);
        float h2 = hash11(variation * 419.2 + float(id) * 0.0047);
        cr = 0.65 + (h0 - 0.5) * 0.18;
        cg = 0.18 + (h1 - 0.5) * 0.12;
        cb = 0.85 + (h2 - 0.5) * 0.14;
        float sparkle = hash11(px * 0.21 + py * 0.27 + variation);
        float bright = step(0.60, sparkle) * 0.30;
        cr += bright * 0.8;
        cg += bright * 0.3;
        cb += bright;
        float glint = step(0.82, hash11(variation * 59.3 + float(id) * 0.005)) * 0.35;
        cr += glint * 0.6; cg += glint * 0.3; cb += glint;
        float depth = 1.0 - (py / rf(O_P + 3u)) * 0.2;
        cr *= depth; cg *= depth; cb *= depth;
        float ore_glow = 0.15;
        float final_light = min(light + ore_glow, 1.0);
        cr *= final_light; cg *= final_light; cb *= final_light;

        // Sonar also reveals purple ore
        float sonar_on = rf(O_P + 30u);
        float sonar_r = rf(O_P + 31u);
        if (sonar_on > 0.5 && sonar_r > 1.0) {
            float sonar_cx = rf(O_P + 32u), sonar_cy = rf(O_P + 33u);
            float sdist = length(vec2(px - sonar_cx, py - sonar_cy));
            if (sdist < sonar_r) {
                float behind = (sonar_r - sdist) / 300.0;
                float reveal = clamp(1.0 - behind * 2.5, 0.0, 1.0);
                reveal *= reveal;
                float pulse = 0.8 + 0.2 * sin(sdist * 0.15 + sonar_r * 0.1);
                float glow = reveal * 0.85 * pulse;
                cr = mix(cr, 0.8, glow);
                cg = mix(cg, 0.2, glow);
                cb = mix(cb, 1.0, glow);
            }
        }

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

    // --- Standard materials (sand, clay, rock, stone, hard rock, copper, bedrock) ---
    // (lava mat 10 redirected to density buffer above, composited by render_water)
    } else {
        // Base color from material property table
        cr = rf(O_M + mat * 12u + 6u);
        cg = rf(O_M + mat * 12u + 7u);
        cb = rf(O_M + mat * 12u + 8u);

        // Per-particle color variation: 3 independent hashes give RGB jitter.
        // Uses variation (from fractional material) + particle ID for stable uniqueness.
        float h0 = hash11(variation * 127.1 + float(id) * 0.0013);
        float h1 = hash11(variation * 269.5 + float(id) * 0.0029);
        float h2 = hash11(variation * 419.2 + float(id) * 0.0047);
        // Stone (mat 4) varies less: a lump reads as one pale thing
        // against the ground's grain. Hard rock (5) and bedrock (7) are
        // smoother still, so a seam of either reads as one slab.
        float var_strength = (mat == 4u) ? 0.07 : ((mat == 5u) ? 0.10 : ((mat == 7u) ? 0.04 : 0.22));
        cr += (h0 - 0.5) * var_strength;
        cg += (h1 - 0.5) * var_strength;
        cb += (h2 - 0.5) * var_strength;

        // Position-dependent noise: prevents banding when many same-material particles cluster
        float pos_hash = hash11(px * 0.031 + py * 0.017);
        cr += (pos_hash - 0.5) * 0.08;
        cg += (hash11(pos_hash * 3.7) - 0.5) * 0.08;
        cb += (hash11(pos_hash * 7.3) - 0.5) * 0.08;

        // Water: extra blue shimmer for translucent look
        if (mat == 1u) {
            float shimmer = hash11(px * 0.07 + py * 0.13 + variation) * 0.1;
            cb += 0.08 + shimmer;
            cg += 0.03;
        }

        // Hard rock: a few pale flecks, so it reads as a different stone
        // from the plain rock round it, not just a darker patch of it.
        if (mat == 5u) {
            float fleck = step(0.94, hash11(variation * 41.7 + float(id) * 0.007)) * 0.14;
            cr += fleck; cg += fleck; cb += fleck * 1.1;
        }
        // Copper: warm patina with orange-tinted glints (18% chance)
        if (mat == 6u) {
            float patina = hash11(px * 0.11 + py * 0.17 + variation);
            cr += patina * 0.12;
            cg += patina * 0.06;
            float glint = step(0.82, hash11(variation * 53.3 + float(id) * 0.009)) * 0.25;
            cr += glint; cg += glint * 0.7; // warm glint (less green)
        }
        // Bedrock: faint level banding, a slab laid down in sheets.
        if (mat == 7u) {
            float band = sin(py * 0.11 + hash11(floor(py / 24.0)) * 3.0) * 0.025;
            cr += band; cg += band; cb += band * 1.3;
        }

        // Depth gradient: particles lower in the world are subtly darker (up to 20%)
        float depth = 1.0 - (py / rf(O_P + 3u)) * 0.2;
        cr *= depth;
        cg *= depth;
        cb *= depth;
    }

    // Ores and lava emit their own light so they're visible even in darkness
    float ore_glow = 0.0;
    if (mat == 6u) ore_glow = 0.10;  // copper: faint glow
    // mat 10 (lava) redirected to density buffer above; rendered by render_water
    if (mat == 12u) ore_glow = 0.15; // purple ore: moderate glow

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
    if (chunk != 0u) {
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
}
