#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0) uniform sampler2DArray mix_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        ivec2 rastered_size; int channel_mode; int split_count;
        ivec3 view_channel; int view_split_flag;
    } int_params;
layout (set = 0, binding = 2) uniform sampler1D curve_tex;

layout (rgba16f, set = 1, binding = 0) uniform image2D target_tex;

const int CMY_MODE = 0;
const int RGB_MODE = 1;

float map(float val, float s_min, float s_max, float d_min, float d_max) {
    float ratio = clamp((val - s_min) / (s_max - s_min), 0.0, 1.0);
    return mix(d_min, d_max, ratio);
}

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 isize = ivec2(int_params.rastered_size);
    int channel_mode = int_params.channel_mode;
    int split_count = int_params.split_count;
    ivec3 view_channel = int_params.view_channel;
    int view_split_flag = int_params.view_split_flag;

    vec2 uv = (vec2(iuv) + 0.5) / isize;

    if (iuv.x >= isize.x || iuv.y >= isize.y) {
        return;
    }

    vec3 target_col = vec3(0.0);

    bool split_enable = split_count > 1;
    if (split_enable) {
        for (int channel_idx = 0; channel_idx < 3; channel_idx++) {
            int split_flag = 1;
            float skipped_count = 0.0;
            for (int split_idx = 0; split_idx < split_count; split_idx++) {

                int layer_idx = channel_idx * split_count + split_idx;
                vec3 origin_col = imageLoad(target_tex, iuv).rgb;
                if (channel_mode == CMY_MODE)
                    origin_col = vec3(1.0) - origin_col;
                float alpha = texture(mix_tex, vec3(uv, layer_idx)).r;
                vec4 mix_col = vec4(origin_col, alpha);

                float split_min = split_idx / float(split_count);
                float split_max = (split_idx + 1) / float(split_count);
                float strength = map(mix_col[channel_idx], split_min, split_max, 0.0, 1.0);
                strength = texture(curve_tex, strength).r;
                strength = strength * mix_col.a * step(0.0, mix_col.a);

                bool is_skipped = (split_flag & view_split_flag) == 0;
                split_flag *= 2;

                if (is_skipped) {
                    skipped_count += strength;
                }
                else {
                    // target_col[channel_idx] += skipped_count + strength; // test
                    if (mix_col.a > 0.0)
                        target_col[channel_idx] = map(strength, 0.0, 1.0, split_min, split_max);
                    skipped_count = 0.0;
                }
            }
        }

        // target_col = target_col / float(split_count); // test
    }
    else {
        target_col = imageLoad(target_tex, iuv).rgb;
        if (channel_mode == CMY_MODE)
            target_col = vec3(1.0) - target_col;
    }

    target_col = target_col * view_channel;

    if (channel_mode == CMY_MODE)
        target_col = vec3(1.0) - target_col;
    
    imageStore(target_tex, iuv, vec4(target_col, 1.0));
}
