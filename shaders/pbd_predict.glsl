#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

// Spatial grid: GW×GH cells, up to MPC particles per cell, PC total particles
const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
// SSBO section offsets: Params, Materials, GridCounts, GridParticles, ParticleData, RenderOutput
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
// Feedback block at the SSBO tail (see simulation.gd O_FB):
// [0] player contact count, [1] creature kills, [2] impact count, [3..] impact entries
const uint O_FB = 8237003u;
// Bond records at the SSBO tail (see sim.gd O_BD): per particle [chunk
// id, awake, bond count, pad, then NB pairs of (mate index, rest length)].
// A chunk is a lump of loose material (a boulder, a stone, a clump of
// clay) whose particles are bonded to their lattice neighbours; chunk id
// 0 means none. Capsule slots (see pbd_delta) with a mode below -1.5
// are chunk events this shader handles: -2 pull (unit dir, speed in the
// radius field, chunk id in half_length), -3 eat (chunk id in
// half_length, radius), -4 break (radius).
const uint O_BD = 8813070u;
const uint BD = 20u;
const uint NB = 8u;
const uint NONE = 0xFFFFFFFFu;
const uint O_CAP = 8236939u;
const uint N_CAP = 8u;
// Cell classes per render pixel, last tick's (render_write.glsl): 0 air,
// 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell.
const uint O_CT = 8294670u;
const uint O_LN = 22291598u;   // cell classes with crumbs marked (cell_post.glsl), last tick's: 256 added on a crumb
const uint O_LP = 22291470u;   // light and flow parameters (sim.gd): from [96] two currents, 8 floats each: x0 y0 x1 y1 dx dy speed on
// Skinned chunks (sim.gd O_SK, O_BN): per particle [bone + 1, the next
// bone's weight, rest x, rest y]; per bone [x, y, cos, sin, rest x,
// rest y, rest cos, rest sin, drive, stretch along, pad, pad].
const uint O_SK = 22939598u;
const uint O_BN = 25013198u;
const uint BN = 12u;
// Slime brains (sim.gd O_SB): [x, y, reach, pull, drift x, drift y, drift speed, on] each.
const uint O_SB = 25039822u;
const uint N_SLIME = 16u;



float rf(uint i) { return uintBitsToFloat(buf.d[i]); }    // Read float from flat uint SSBO
void wf(uint i, float v) { buf.d[i] = floatBitsToUint(v); } // Write float to flat uint SSBO

// Where bone k carries a particle laid out at rest place r: r in the
// bone's rest frame, stretched along the bone, in its frame now.
vec2 bone_place(uint k, vec2 r) {
    uint o = O_BN + k * BN;
    vec2 d = r - vec2(rf(o + 4u), rf(o + 5u));
    float c0 = rf(o + 6u), s0 = rf(o + 7u);
    vec2 l = vec2(c0 * d.x + s0 * d.y, -s0 * d.x + c0 * d.y);
    l.x *= rf(o + 9u);
    float c = rf(o + 2u), s = rf(o + 3u);
    return vec2(rf(o), rf(o + 1u)) + vec2(c * l.x - s * l.y, s * l.x + c * l.y);
}

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
    // A skinned particle whose bone was let go with a chunk id of its
    // own (sim.gd release_bones) joins that chunk: the piece cut off a
    // stem falls as a lump of its own, its bonds to the rest broken.
    // A bone let go split across (a shroom's cap) gives each piece of
    // it its own id, by where the particle lay across the bone's axis
    // at rest: the pieces fall apart as lumps of their own.
    bool woke = false;
    if (chunk != 0u) {
        uint sk0 = buf.d[O_SK + id * 4u];
        if (sk0 > 0u) {
            uint o = O_BN + (sk0 - 1u) * BN;
            uint nid = uint(rf(o + 10u));
            float pieces = rf(o + 11u);
            if (rf(o + 8u) < 0.5 && pieces > 1.5 && nid > 0u) {
                vec2 rel = vec2(rf(O_SK + id * 4u + 2u) - rf(o + 4u), rf(O_SK + id * 4u + 3u) - rf(o + 5u));
                float across = dot(rel, vec2(-rf(o + 7u), rf(o + 6u)));
                nid += uint(clamp(floor(across / max(rf(o + 9u), 1.0) + pieces * 0.5), 0.0, pieces - 1.0));
            }
            if (rf(o + 8u) < 0.5 && nid > 0u && nid != chunk) {
                // Woken as it goes: a lump at rest sleeps, and with
                // nothing under it now it must fall.
                chunk = nid;
                buf.d[bd] = nid;
                woke = true;
            }
        }
    }
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
                // fly apart a little (a wake, mode -5, is pbd_delta's).
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

    // --- A skinned chunk's particle (sim.gd O_SK) whose bone is driven
    //     goes where its bones carry its rest place, a blend of two, at
    //     the speed that takes it there in a tick; the solver leaves it
    //     there (pbd_delta). A particle struck loose is no longer bonded
    //     and falls as a grain. ---
    bool driven = false;
    vec2 drive_to = vec2(0.0);
    if (bonded && chunk != 0u) {
        uint sk = buf.d[O_SK + id * 4u];
        if (sk > 0u) {
            uint k = sk - 1u;
            if (rf(O_BN + k * BN + 8u) > 0.5) {
                vec2 r = vec2(rf(O_SK + id * 4u + 2u), rf(O_SK + id * 4u + 3u));
                float w = rf(O_SK + id * 4u + 1u);
                drive_to = bone_place(k, r);
                if (w > 0.0) drive_to = mix(drive_to, bone_place(k + 1u, r), w);
                driven = true;
            }
        }
    }

    // --- A slime's particle: drawn toward its brain's centre (the
    //     nearest brain whose reach it is in) and along its drift, so
    //     the blob holds together and creeps; out of every reach it is
    //     an inert puddle. A strike splatters it. ---
    float grav_k = 1.0;
    if (mat == 14u) {
        float best = 1e9;
        uint bi = N_SLIME;
        for (uint i = 0u; i < N_SLIME; i++) {
            uint o = O_SB + i * 8u;
            if (rf(o + 7u) < 0.5) continue;
            float d = length(vec2(px, py) - vec2(rf(o), rf(o + 1u)));
            if (d < rf(o + 2u) && d < best) { best = d; bi = i; }
        }
        if (bi < N_SLIME) {
            // A live slime bears part of its own weight, so it stands
            // as a mound rather than running flat.
            grav_k = 0.3;
            uint o = O_SB + bi * 8u;
            vec2 to = vec2(rf(o), rf(o + 1u)) - vec2(px, py);
            float dl = length(to);
            float pull = rf(o + 3u);
            if (dl > 0.5) {
                vec2 a = to / dl * min(dl * pull, 900.0);
                vx += a.x * dt;
                vy += a.y * dt;
            }
            vec2 drift = vec2(rf(o + 4u), rf(o + 5u)) * rf(o + 6u);
            vx += (drift.x - vx) * 0.15;
            if (drift.y != 0.0) vy += (drift.y - vy) * 0.15;
        }
        for (uint c = 0u; c < N_CAP; c++) {
            uint slot = O_CAP + c * 8u;
            if (rf(slot + 6u) < 0.5 || rf(slot + 7u) > -3.5 || rf(slot + 7u) < -4.5) continue;
            vec2 off = vec2(px, py) - vec2(rf(slot), rf(slot + 1u));
            float d = length(off);
            if (d < rf(slot + 4u) && d > 0.01) {
                vx += off.x / d * 160.0;
                vy += off.y / d * 160.0 - 60.0;
            }
        }
    }

    // --- Crumbs: a static particle whose cell was marked a crumb last
    //     tick (cell_post.glsl: a bit of rock of at most N cells) comes
    //     loose as stone when the gecko's body (the pusher capsules,
    //     mode -1) touches it, so the body shoves it out of its way as it
    //     does a grain instead of catching on it, and it falls ---
    bool loosened = false;
    if (!bonded && yield_s >= 5.0 && (mat == 3u || mat == 5u || mat == 6u) && rf(O_P + 23u) > 0.5) {
        float cpsz = rf(O_P + 18u);
        uint crw = uint(rf(O_P + 16u)), crh = uint(rf(O_P + 17u));
        int crx = int(floor(px / cpsz)), cry = int(floor(py / cpsz));
        if (crx >= 0 && cry >= 0 && crx < int(crw) && cry < int(crh) && buf.d[O_LN + uint(cry) * crw + uint(crx)] >= 256u) {
            for (uint c = 0u; c < N_CAP && !loosened; c++) {
                uint slot = O_CAP + c * 8u;
                if (rf(slot + 6u) < 0.5) continue;
                float mode = rf(slot + 7u);
                if (mode > -0.5 || mode < -1.5) continue;
                vec2 ca = vec2(rf(slot), rf(slot + 1u));
                vec2 cd = vec2(rf(slot + 2u), rf(slot + 3u));
                float cr = rf(slot + 4u), chl = rf(slot + 5u);
                vec2 p0 = ca - cd * chl, ba = cd * chl * 2.0;
                vec2 pa = vec2(px, py) - p0;
                float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
                if (length(pa - ba * t) < cr + 2.0) loosened = true;
            }
        }
    }
    if (loosened) {
        mat_f = 4.0 + min(fract(mat_f), 0.088);
        mat = 4u;
        yield_s = rf(O_M + 4u * 12u + 5u);
        wf(b + 7u, mat_f);
    }

    bool awake = loosened || has_velocity || near_drill || (mat == 1u) || (mat == 10u) || (mat == 13u) || (mat == 14u) || is_ephemeral || mates_moving || pulled || driven || woke;

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
            vy += dt * gravity * grav_k;
        }
    }

    // --- Currents: water inside a flow rect is drawn toward the flow's
    //     velocity, so a channel runs and carries what swims in it. ---
    if (mat == 1u) {
        for (uint ci = 0u; ci < 2u; ci++) {
            uint cb = O_LP + 96u + ci * 8u;
            if (rf(cb + 7u) < 0.5) continue;
            if (px >= rf(cb) && px < rf(cb + 2u) && py >= rf(cb + 1u) && py < rf(cb + 3u)) {
                float spd = rf(cb + 6u);
                vx += (rf(cb + 4u) * spd - vx) * 0.12;
                vy += (rf(cb + 5u) * spd - vy) * 0.12;
            }
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
    if (driven) {
        vx = (drive_to.x - px) / dt;
        vy = (drive_to.y - py) / dt;
    }

    float predx = awake ? (px + dt * vx) : px;
    float predy = awake ? (py + dt * vy) : py;
    if (driven) {
        predx = drive_to.x;
        predy = drive_to.y;
    }

    // --- Congestion damping (never for a chunk's particles: a lump is
    //     dense by nature, and damping its inside but not its edge
    //     would tear it apart as it moves) ---
    float cs = rf(O_P + 6u);
    uint congest_limit = (mat == 1u || mat == 10u || mat == 14u || is_ephemeral) ? 12u : 6u;
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
