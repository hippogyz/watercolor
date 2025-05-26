#[compute]
#version 450


layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (std430, set = 0, binding = 0) restrict buffer IntParams {
        ivec2 rastered_size; ivec2 reserved_02;
    } int_params;
layout (std430, set = 0, binding = 1) restrict buffer FloatParams{
        vec3 inside_col; float radius;
        vec3 outside_col; float reserved_11;
    } float_params;

layout (rgba16f, set = 1, binding = 0) uniform image2D target_tex;

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 isize = ivec2(int_params.rastered_size);
    float radius = float_params.radius;
    vec3 inside_col = float_params.inside_col;
    vec3 outside_col = float_params.outside_col;

    if (iuv.x >= isize.x || iuv.y >= isize.y)
        return;
    
    vec2 uv = (vec2(iuv) + vec2(0.5)) / isize;
    float y_to_x = float(isize.x) / float(isize.y);
    vec2 to_center = (uv - 0.5) * vec2(y_to_x, 1.0);
    float dist2 = dot(to_center, to_center);

    vec3 col = mix(inside_col, outside_col, step(radius * radius, dist2));
    imageStore(target_tex, iuv, vec4(col, 1.0));
}
