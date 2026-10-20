#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

// Spatial grid: GW×GH cells, up to MPC particles per cell, PC total particles
const uint GW = 160u, GH = 90u, MPC = 32u, PC = 129600u;
// SSBO section offsets: Params, Materials, GridCounts, GridParticles, ParticleData, RenderOutput
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 14536u, O_PT = 475336u, O_RN = 1512136u;
// Feedback block at the SSBO tail (see simulation.gd O_FB):
// [0] player contact count, [1] creature kills, [2] impact count, [3..] impact entries
const uint O_FB = 2059403u;
// Bond records at the SSBO tail (see sim.gd O_BD): per particle [chunk
// id, awake, bond count, pad, then NB pairs of (mate index, rest length)].
// A chunk is a lump of loose material (a boulder, a stone, a clump of
// clay) whose particles are bonded to their lattice neighbours; chunk id
// 0 means none. Capsule slots (see pbd_delta) with a mode below -1.5
// are chunk events this shader handles: -2 pull (unit dir, speed in the
// radius field, chunk id in half_length), -3 eat (chunk id in
// half_length, radius), -4 break (radius).
const uint O_BD = 2203470u;
const uint BD = 20u;
const uint NB = 8u;
const uint NONE = 0xFFFFFFFFu;
const uint O_CAP = 2059339u;
const uint N_CAP = 8u;
// Cell classes per render pixel, last tick's (render_write.glsl): 0 air,
// 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell.
const uint O_CT = 2073870u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }    // Read float from flat uint SSBO
void wf(uint i, float v) { buf.d[i] = floatBitsToUint(v); } // Write float to flat uint SSBO

// Shared explosion logic: radial impulse + conversion to fire/smoke.
// implode = true reverses the impulse (pull inward) and skips every material
// conversion, so imploded material moves but stays what it is.
void apply_explosion(uint id, uint b, float exp_r, float exp_x, float exp_y,
                     float px, float py, inout float vx, inout float vy,
                     inout uint mat, inout bool is_ephemeral, inout bool awake,
                     bool implode) {
    float edx = px - exp_x;
    float edy = py - exp_y;
    float edist = length(vec2(edx, edy));
    if (edist < exp_r && edist > 0.5) {
        float strength = 1.0 - edist / exp_r;
        float impulse = strength * exp_r * 20.0;
        float dir_sign = implode ? -1.0 : 1.0;
        vx += dir_sign * (edx / edist) * impulse;
        vy += dir_sign * (edy / edist) * impulse;
        awake = true;

        if (!implode && mat < 8u && mat != 1u) {
            uint hash = id * 2654435761u;
            float rand_val = float(hash >> 16u) / 65535.0;
            uint hash2 = hash * 747796405u + 2891336453u;
            float lava_var = float(hash2 >> 16u) / 65535.0;
            if (strength > 0.4) {
                if (rand_val < 0.03) {
                    wf(b + 7u, 10.0 + lava_var * 0.099);
                    mat = 10u;
                } else if (rand_val < 0.20) {
                    wf(b + 7u, 9.099);
                    mat = 9u;
                    is_ephemeral = true;
                } else if (rand_val < 0.82) {
                    wf(b + 7u, 8.099);
                    mat = 8u;
                    is_ephemeral = true;
                }
            } else if (strength > 0.15) {
                if (rand_val < 0.015) {
                    wf(b + 7u, 10.0 + lava_var * 0.099);
                    mat = 10u;
                } else if (rand_val < 0.12) {
                    wf(b + 7u, 9.099);
                    mat = 9u;
                    is_ephemeral = true;
                } else if (rand_val < 0.52) {
                    wf(b + 7u, 8.099);
                    mat = 8u;
                    is_ephemeral = true;
                }
            } else if (strength > 0.05) {
                if (rand_val < 0.25) {
                    wf(b + 7u, 8.099);
                    mat = 8u;
                    is_ephemeral = true;
                }
            }
        }
        // Purple ore (mat 12) also converts to fire/smoke/lava
        if (!implode && mat == 12u) {
            uint hash = id * 2654435761u;
            float rand_val = float(hash >> 16u) / 65535.0;
            uint hash2 = hash * 747796405u + 2891336453u;
            float lava_var = float(hash2 >> 16u) / 65535.0;
            if (strength > 0.3) {
                if (rand_val < 0.04) {
                    wf(b + 7u, 10.0 + lava_var * 0.099); mat = 10u;
                } else if (rand_val < 0.25) {
                    wf(b + 7u, 9.099); mat = 9u; is_ephemeral = true;
                } else if (rand_val < 0.90) {
                    wf(b + 7u, 8.099); mat = 8u; is_ephemeral = true;
                }
            } else if (strength > 0.1) {
                if (rand_val < 0.40) {
                    wf(b + 7u, 8.099); mat = 8u; is_ephemeral = true;
                }
            }
        }
        // Creature particles die in explosions. Count the body half once.
        if (mat == 13u && strength > 0.25) {
            float mat_raw = rf(b + 7u);
            uint mat_enc = uint(round(fract(mat_raw) * 1000.0));
            if ((mat_enc & 1u) == 0u) atomicAdd(buf.d[O_FB + 1u], 1u);
            wf(b, -1000.0); wf(b + 1u, -1000.0);
            wf(b + 2u, 0.0); wf(b + 3u, 0.0);
            wf(b + 4u, -1000.0); wf(b + 5u, -1000.0);
            wf(b + 7u, 0.0);
            mat = 0u;
        }
    }
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    float dt = rf(O_P);
    float gravity = rf(O_P + 1u);

    uint b = O_PT + id * 8u;
    float px = rf(b), py = rf(b + 1u);
    float vx = rf(b + 2u), vy = rf(b + 3u);
    float mat_f = rf(b + 7u);
    uint mat = uint(mat_f);

    // --- Bullet particles: no PBD, just advance position ---
    // The fraction encodes the bullet kind (11.0 + kind * 0.01).
    // Lobbed kinds (4 cluster shell, 5 bomblet) fall under gravity.
    if (mat == 11u) {
        wf(b + 6u, 0.0); // reset collision-check flag used by pbd_delta
        uint kind = uint(round(fract(mat_f) * 100.0));
        if (kind == 4u || kind == 5u) vy += dt * gravity * 0.55;
        float predx = px + dt * vx;
        float predy = py + dt * vy;
        wf(b + 2u, vx);
        wf(b + 3u, vy);
        wf(b + 4u, predx);
        wf(b + 5u, predy);
        atomicAdd(buf.d[O_P + 39u], 1u);
        return;
    }

    // Yield strength from material table; ephemerals, purple ore, and NPCs use hardcoded values
    float yield_s;
    if (mat < 8u) {
        yield_s = rf(O_M + mat * 12u + 5u);
    } else if (mat == 12u) {
        yield_s = 8.0;   // glowshroom: held in place like rock
    } else {
        yield_s = 0.0;
    }

    // NPC particles apply full gravity via the awake path (yield_s = 0 < 5.0)

    bool has_velocity = (abs(vx) > 0.01 || abs(vy) > 0.01);

    // --- Drill proximity test ---
    bool near_drill = false;
    if (rf(O_P + 15u) > 0.5) {
        float dpx = rf(O_P + 9u), dpy = rf(O_P + 10u);
        if (yield_s >= 5.0) {
            float ddx = px - dpx, ddy = py - dpy;
            near_drill = (ddx * ddx + ddy * ddy < 22500.0);
        } else {
            float dx = rf(O_P + 11u), dy = rf(O_P + 12u);
            float dr = rf(O_P + 13u), dhl = rf(O_P + 14u);
            vec2 a = vec2(dpx - dx * dhl, dpy - dy * dhl);
            vec2 bv = vec2(dpx + dx * dhl, dpy + dy * dhl);
            vec2 p = vec2(px, py);
            vec2 pa = p - a, ba = bv - a;
            float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
            float dist = length(p - (a + ba * t));
            near_drill = (dist < dr + 5.0);
        }
    }

    bool is_ephemeral = (mat == 8u || mat == 9u);

    // --- Chunks: a bonded particle wakes with its mates, so a lump
    //     pushed at one end moves as a whole; and the chunk events in
    //     the capsule slots: pull, eat, break ---
    uint bd = O_BD + id * BD;
    uint chunk = buf.d[bd];
    bool bonded = chunk != 0u;
    bool mates_moving = false;
    bool pulled = false;
    float pull_vx = 0.0, pull_vy = 0.0;
    if (bonded) {
        for (uint k = 0u; k < NB; k++) {
            uint j = buf.d[bd + 4u + k * 2u];
            if (j == NONE) continue;
            uint bj = O_PT + j * 8u;
            if (abs(rf(bj + 2u)) > 0.01 || abs(rf(bj + 3u)) > 0.01) {
                mates_moving = true;
                break;
            }
        }
        for (uint c = 0u; c < N_CAP; c++) {
            uint slot = O_CAP + c * 8u;
            if (rf(slot + 6u) < 0.5) continue;
            float mode = rf(slot + 7u);
            if (mode > -1.5) continue;
            vec2 cpos = vec2(rf(slot), rf(slot + 1u));
            float cr = rf(slot + 4u);
            float d = length(vec2(px, py) - cpos);
            if (mode < -3.5) {
                // A strike: every bond within reach breaks and the grains
                // fly apart a little.
                if (d < cr) {
                    for (uint k = 0u; k < NB; k++) buf.d[bd + 4u + k * 2u] = NONE;
                    buf.d[bd] = 0u;
                    buf.d[bd + 2u] = 0u;
                    chunk = 0u;
                    uint hsh = id * 2654435761u;
                    float a = float(hsh >> 16u) / 65535.0 * 6.2831853;
                    float m = 30.0 + float((hsh * 747796405u) >> 20u) / 4095.0 * 50.0;
                    vx += cos(a) * m;
                    vy += sin(a) * m;
                    mates_moving = true;
                }
            } else if (mode < -2.5) {
                // Swallowed: the chunk's particles within reach vanish.
                if (chunk == uint(rf(slot + 5u)) && d < cr) {
                    wf(b, -1000.0); wf(b + 1u, -1000.0);
                    wf(b + 2u, 0.0); wf(b + 3u, 0.0);
                    wf(b + 4u, -1000.0); wf(b + 5u, -1000.0);
                    wf(b + 7u, 0.0);
                    for (uint k = 0u; k < NB; k++) buf.d[bd + 4u + k * 2u] = NONE;
                    buf.d[bd] = 0u;
                    buf.d[bd + 1u] = 0u;
                    buf.d[bd + 2u] = 0u;
                    return;
                }
            } else if (chunk == uint(rf(slot + 5u))) {
                // Dragged by the tongue: the whole chunk moves toward the
                // mouth at the pull speed, gravity or not.
                pulled = true;
                pull_vx = rf(slot + 2u) * cr;
                pull_vy = rf(slot + 3u) * cr;
            }
        }
    }

    bool awake = has_velocity || near_drill || (mat == 1u) || (mat == 10u) || (mat == 13u) || is_ephemeral || mates_moving || pulled;

    // --- Loose grains fall when undermined. The solver only moves what
    //     is awake, and a grain at rest sleeps, so a bite under a bed of
    //     sand left the sand hanging. A sleeping grain (sand, clay, the
    //     stone of a broken lump: yield under 5, no bonds) wakes when
    //     the cell under it, or either cell diagonally under it, read
    //     as open (air, water, lava) last tick. A heap flows until no
    //     face is steeper than the cells' diagonal, then sleeps again;
    //     a hole's rim caves in from the row above, so a hopper empties
    //     through a cone. ---
    if (!awake && !bonded && mat < 8u && mat != 1u && yield_s < 5.0) {
        float psz = rf(O_P + 18u);
        int rw = int(rf(O_P + 16u)), rh = int(rf(O_P + 17u));
        int rx = int(floor(px / psz)), ry = int(floor(py / psz));
        if (rx >= 0 && rx < rw && ry >= 0 && ry + 1 < rh) {
            uint row = O_CT + uint(ry + 1) * uint(rw);
            for (int s = -1; s <= 1 && !awake; s++) {
                int sx = rx + s;
                if (sx < 0 || sx >= rw) continue;
                uint under = buf.d[row + uint(sx)];
                if (under == 0u || under == 1u || under == 3u) awake = true;
            }
        }
    }
    if (bonded) buf.d[bd + 1u] = awake ? 1u : 0u;

    // --- Explosion slot 1 ---
    // A negative encoded position marks an implosion. Decode with abs().
    // The sign lives on the position because pbd_finalize reads radius > 0.
    float exp_r = rf(O_P + 28u);
    if (exp_r > 0.0) {
        float encoded = rf(O_P + 29u);
        bool implode1 = encoded < 0.0;
        encoded = abs(encoded);
        float exp_x = mod(encoded, 2048.0);
        float exp_y = floor(encoded / 2048.0);
        apply_explosion(id, b, exp_r, exp_x, exp_y, px, py, vx, vy, mat, is_ephemeral, awake, implode1);
    }

    // --- Explosion slot 2 ---
    float exp_r2 = rf(O_P + 37u);
    if (exp_r2 > 0.0) {
        float encoded2 = rf(O_P + 38u);
        bool implode2 = encoded2 < 0.0;
        encoded2 = abs(encoded2);
        float exp_x2 = mod(encoded2, 2048.0);
        float exp_y2 = floor(encoded2 / 2048.0);
        apply_explosion(id, b, exp_r2, exp_x2, exp_y2, px, py, vx, vy, mat, is_ephemeral, awake, implode2);
    }

    if (awake) {
        atomicAdd(buf.d[O_P + 39u], 1u);
    }

    // --- Apply gravity based on material type ---
    if (awake) {
        if (mat == 9u) {
            vy -= dt * gravity * 0.15;
        } else if (mat == 8u) {
            vy += dt * gravity * 0.3;
        } else if (mat == 13u) {
            vy += dt * gravity;
        } else if (mat == 10u) {
            vy += dt * gravity;
        } else if (yield_s < 5.0) {
            vy += dt * gravity;
        }
    }

    // NPC velocity clamp: horizontal tight to prevent tunneling, vertical allows jumps
    if (mat == 13u) {
        vx = clamp(vx, -50.0, 50.0);
        vy = clamp(vy, -110.0, 50.0);
    }

    if (pulled) {
        vx = pull_vx;
        vy = pull_vy;
    }

    float predx = awake ? (px + dt * vx) : px;
    float predy = awake ? (py + dt * vy) : py;

    // --- Congestion damping (never for a chunk's particles: a lump is
    //     dense by nature, and damping its inside but not its edge
    //     would tear it apart as it moves) ---
    float cs = rf(O_P + 6u);
    uint congest_limit = (mat == 1u || mat == 10u || is_ephemeral) ? 12u : 6u;
    if (has_velocity && !bonded && (abs(vx) > 2.0 || abs(vy) > 2.0)) {
        int pcx = int(floor(predx / cs));
        int pcy = int(floor(predy / cs));
        if (pcx >= 0 && pcx < int(GW) && pcy >= 0 && pcy < int(GH)) {
            uint cell = uint(pcy) * GW + uint(pcx);
            uint count = buf.d[O_GC + cell];
            if (count > congest_limit) {
                vx *= 0.5;
                vy *= 0.5;
                predx = px + dt * vx;
                predy = py + dt * vy;
            }
        }
    }

    wf(b + 2u, vx);
    wf(b + 3u, vy);
    wf(b + 4u, predx);
    wf(b + 5u, predy);
}
