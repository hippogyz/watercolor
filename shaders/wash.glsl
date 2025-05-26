#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0) uniform sampler2DArray blurred_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        ivec2 rastered_size; ivec2 reserved_02;
    } int_params;

layout (r16f, set = 1, binding = 0) uniform image2DArray target_tex;

layout (std430, set = 2, binding = 0) restrict buffer EdgeParams {
        float edge_min; float edge_max; float edge_pow; float reserved_01;
    } edge_params;

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    int layer = int(gl_GlobalInvocationID.z);
    ivec2 isize = ivec2(int_params.rastered_size);
    vec2 uv = (vec2(iuv) + 0.5) / isize;

    if (iuv.x >= isize.x || iuv.y >= isize.y)
        return;

    float edge_min = edge_params.edge_min;
    float edge_max = edge_params.edge_max;
    float edge_pow = edge_params.edge_pow;

    // main process
    float val = texture(blurred_tex, vec3(uv, layer)).r;
    float threshold = step(0.5, val);

    val += 0.4 * 0.5 * (1.0 + sin(20.0 * uv.x) * sin(20.0 * uv.y));
    val = 2.0 - val * 2.0;
    val = pow(abs(val), edge_pow) * (edge_max - edge_min) + edge_min;
    val *= threshold;

    imageStore(target_tex, ivec3(iuv, layer), vec4(val));
}
