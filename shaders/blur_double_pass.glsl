#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0) uniform sampler2DArray source_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        ivec2 blur_tex_size; int sample_count; int reserved_01;
    } int_params;
layout (std430, set = 0, binding = 2) restrict buffer SampleInfos {
        vec4[] sample_info;
    } sample_infos;

layout (r16f, set = 1, binding = 0) uniform image2DArray blurred_tex;

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    int layer = int(gl_GlobalInvocationID.z);
    ivec2 blur_tex_size = int_params.blur_tex_size;

    if (iuv.x >= blur_tex_size.x || iuv.y >= blur_tex_size.y)
        return;
    
    vec2 uv = (vec2(iuv) + vec2(0.5)) / blur_tex_size;
    float val = 0.0;
    float w = 0.0;

    int sample_count = int_params.sample_count;
    for (int i = 0; i < sample_count; i++)
    {
        vec4 sample_info = sample_infos.sample_info[i];
        vec2 sample_uv = sample_info.xy + uv;
        float weight = sample_info.z;

        val += texture(source_tex, vec3(sample_uv, float(layer))).r * weight;
        w += weight;
    }

    val = val / w;
    imageStore(blurred_tex, ivec3(iuv, layer), vec4(val));
}
