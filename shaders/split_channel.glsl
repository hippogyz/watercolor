#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (rgba16f, set = 0, binding = 0) uniform image2D source_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        ivec2 rastered_size; int channel_mode; int split_count;
    } int_params;

layout (r16f, set = 1, binding = 0) uniform image2DArray splitted_tex;

const int CMY_MODE = 0;
const int RGB_MODE = 1;

float split(vec4 source_col, int channel_idx, float split_threshold) {
    float strength = source_col[channel_idx];
    return step(split_threshold, strength);
}

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 isize = ivec2(int_params.rastered_size);
    int channel_mode = int_params.channel_mode;
    int split_count = int_params.split_count;

    if (iuv.x >= isize.x || iuv.y >= isize.y) {
        return;
    }

    vec4 source_col = imageLoad(source_tex, iuv);
    if (channel_mode == CMY_MODE)
        source_col.rgb = vec3(1.0) - source_col.rgb;

    for (int channel_idx = 0; channel_idx < 3; channel_idx++) {
        float split_step = 1.0 / float(split_count + 0);

        for (int split_idx = 0; split_idx < split_count; split_idx++) {
            float split_threshold = (split_idx + 0) * split_step;
            float strength = source_col[channel_idx];
            float over_threshold = step(split_threshold, strength);

            int layer_idx = channel_idx * split_count + split_idx;
            imageStore(splitted_tex, ivec3(iuv, layer_idx), vec4(over_threshold));
        }
    }
}
