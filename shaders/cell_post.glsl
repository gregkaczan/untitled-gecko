// Cell post-pass: the cell classes again, with crumbs marked, for the
// gecko's senses (sim.gd reads this copy back, not render_write's). A
// crumb is a bit of matter (static solid, a loose grain, moss,
// crumbling rock) of at most N cells: the cells eight-connected to this
// one within the 5x5 round it, N the crumb threshold (params[23], the
// debug panel's "crumbs pushed"). A speck floating near a wall is a
// crumb, a speck touching the wall is part of it, and a convex corner
// is nine cells or more. A crumb's class is written with 256 added. The
// senses read a crumb as air, so the body is not stopped by a speck or
// caught clinging to one, and pbd_predict.glsl loosens a crumb's
// particle when the body touches it, so the body shoves it aside as it
// does a grain. A chunk's cells are never crumbs. The world's edge
// counts as matter, so a speck on the edge stays what it is.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u;
const uint O_CT = 8294670u;   // cell class per pixel (render_write.glsl)
const uint O_LN = 22291598u;  // the marked copy (sim.gd reads it back)

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

bool matter(uint c) { return c == 2u || c == 4u || c == 5u || c == 6u || c >= 16u; }

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u)), rh = uint(rf(O_P + 17u));
    if (id >= rw * rh) return;
    uint cls = buf.d[O_CT + id];
    uint n = uint(rf(O_P + 23u));
    uint out_v = cls;
    if (n > 0u && matter(cls) && cls < 16u) {
        int x = int(id % rw), y = int(id / rw);
        // The 5x5 as 25 bits, row by row, this cell bit 12.
        uint mask = 0u;
        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                int xx = x + dx, yy = y + dy;
                bool m = (xx < 0 || yy < 0 || xx >= int(rw) || yy >= int(rh)) || matter(buf.d[O_CT + uint(yy) * rw + uint(xx)]);
                if (m) mask |= 1u << uint((dy + 2) * 5 + dx + 2);
            }
        }
        // Grow the component from this cell: sideways within the row,
        // then up and down a row, through matter only, until it stops.
        const uint COL0 = 0x108421u, COL4 = 0x1084210u;
        uint comp = 1u << 12u;
        for (int it = 0; it < 12; it++) {
            uint across = comp | ((comp & ~COL0) >> 1u) | ((comp & ~COL4) << 1u);
            uint grown = (across | (across << 5u) | (across >> 5u)) & mask;
            if (grown == comp) break;
            comp = grown;
        }
        if (bitCount(comp) <= n) out_v = cls + 256u;
    }
    buf.d[O_LN + id] = out_v;
}
