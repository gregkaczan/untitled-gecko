// The light over the world: the sim's light map (light_seed.glsl,
// light_spread.glsl, read back by sim.gd) multiplied over everything
// drawn below, with an ambient floor so the dark is dark grey-blue,
// not black, and the cave's shapes still read.
shader_type canvas_item;
render_mode blend_mul, unshaded;

uniform vec3 ambient = vec3(0.10, 0.11, 0.14);

void fragment() {
    vec3 l = texture(TEXTURE, UV).rgb;
    COLOR = vec4(max(l, ambient), 1.0);
}
