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

layout (set = 3, binding = 0) uniform sampler2D fill_noise_tex;
layout (std430, set = 3, binding = 1) restrict buffer FillParams {
        vec4 strength; // only x channel
        vec2 uv_scale; vec2 uv_offset;
        vec2 uv_offset_shift; float uv_offset_rot; float reserved_31;
    } fill_params;

layout (set = 4, binding = 0) uniform sampler2D border_noise_tex;
layout (std430, set = 4, binding = 1) restrict buffer BorderParams {
        vec4 strength; // only x channel
        vec2 uv_scale; vec2 uv_offset;
        vec2 uv_offset_shift; float uv_offset_rot; float reserved_31;
    } border_params;

vec2 rot_vec2(vec2 source, float angle) {
    vec2 r = vec2(cos(angle), sin(angle));
    return vec2(
        source.x * r.x - source.y * r.y,
        source.x * r.y + source.y * r.x
    );
}

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    int layer = int(gl_GlobalInvocationID.z);
    ivec2 isize = ivec2(int_params.rastered_size);
    vec2 uv = (vec2(iuv) + 0.5) / isize;

    if (iuv.x >= isize.x || iuv.y >= isize.y)
        return;

    // edge
    float edge_min = edge_params.edge_min;
    float edge_max = edge_params.edge_max;
    float edge_pow = edge_params.edge_pow;

    // fill
    float fill_strength = fill_params.strength.x;
    vec2 fill_uv_scale = fill_params.uv_scale;
    vec2 fill_uv_offset = fill_params.uv_offset;
    vec2 fill_uv_offset_shift = fill_params.uv_offset_shift * layer;
    float fill_uv_offset_rot = fill_params.uv_offset_rot * layer;
    vec2 fill_uv = uv * fill_uv_scale + fill_uv_offset;
    fill_uv = rot_vec2(fill_uv, fill_uv_offset_rot);
    fill_uv += fill_uv_offset_shift;
    float fill_noise = texture(fill_noise_tex, fill_uv).r;
    fill_noise = fill_noise * 2.0 - 1.0;
    fill_noise *= fill_strength;

    // border
    float border_strength = border_params.strength.x;
    vec2 border_uv_scale = border_params.uv_scale;
    vec2 border_uv_offset = border_params.uv_offset;
    vec2 border_uv_offset_shift = border_params.uv_offset_shift * layer;
    float border_uv_offset_rot = border_params.uv_offset_rot * layer;
    vec2 border_uv = uv * border_uv_scale + border_uv_offset;
    border_uv = rot_vec2(border_uv, border_uv_offset_rot);
    border_uv += border_uv_offset_shift;
    float border_noise = texture(border_noise_tex, border_uv).r;
    border_noise = border_noise * 2.0 - 1.0;
    border_noise *= border_strength;

    // main process
    float val = texture(blurred_tex, vec3(uv, layer)).r;
    float mask = step(0.5, val + border_noise);

    val += fill_noise;
    val = 2.0 - val * 2.0;
    val = pow(abs(val), edge_pow);
    // val = clamp(val + fill_noise, 0.0, 1.0);
    val = val * (edge_max - edge_min) + edge_min;
    val *= mask;

    val = clamp(val, 0.0, 1.0);
    imageStore(target_tex, ivec3(iuv, layer), vec4(val));
}
