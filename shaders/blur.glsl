#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0) uniform sampler2DArray channel_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        int radial_qual; int polar_qual; int reserved_01; int reserved_011;
        ivec2 blur_tex_size; int split_count; int reserved_11;
    } int_params;
layout (std430, set = 0, binding = 2) restrict buffer FloatParams {
        float blur_radius; float reserved_01; float reserved_011; float reserved_012;
    } float_params;

layout (r16f, set = 1, binding = 0) uniform image2DArray blurred_tex;

const float PI = 3.1415926;

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    int layer = int(gl_GlobalInvocationID.z);
    ivec2 blur_tex_size = int_params.blur_tex_size;
    int split_count = int_params.split_count;
    int layer_count = split_count * 3;
    
    int radial_qual = int_params.radial_qual;
    int polar_qual = int_params.polar_qual;
    float blur_radius = float_params.blur_radius;

    if (iuv.x >= blur_tex_size.x || iuv.y >= blur_tex_size.y)
        return;
    
    vec2 uv = (vec2(iuv) + vec2(0.5)) / blur_tex_size;
    float y_to_x = float(blur_tex_size.x) / float(blur_tex_size.y);

    float f_layer = float(layer);
    float a = texture(channel_tex, vec3(uv, f_layer)).r;
    float sum = 1.0;

    for (int r_idx = 0; r_idx < radial_qual; r_idx++)
    {
        float r = float(r_idx + 1) * blur_radius / (radial_qual + 1);
        float phi = 0.3 * r_idx;
        for (int p_idx = 0; p_idx < polar_qual; p_idx++)
        {
            phi += PI * 2.0 / polar_qual;
            vec2 dir = vec2(cos(phi), sin(phi));
            dir.y *= y_to_x;
            dir *= r;

            vec2 near_uv = uv + dir;
            a += texture(channel_tex, vec3(near_uv, f_layer)).r;
            sum += 1.0;
        }
    }

    a /= sum;

    imageStore(blurred_tex, ivec3(iuv, layer), vec4(a));
}
