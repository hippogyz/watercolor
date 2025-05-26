#[compute]
#version 450

layout (local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout (set = 0, binding = 0) uniform sampler2DArray blurred_tex;
layout (std430, set = 0, binding = 1) restrict buffer IntParams {
        ivec2 screen_size; int view_layer; int reserved_01;
    } int_params;

layout (rgba16f, set = 1, binding = 0) uniform image2D target_tex;

void main() {
    ivec2 iuv = ivec2(gl_GlobalInvocationID.xy);
    ivec2 screen_size = int_params.screen_size;
    int view_layer = int_params.view_layer;

    if (iuv.x >= screen_size.x || iuv.y >= screen_size.y)
        return;
    
    vec2 uv = (vec2(iuv) + vec2(0.5)) / screen_size;
    float layer = float(view_layer);
    
    vec4 debug_col = texture(blurred_tex, vec3(uv, layer));
    imageStore(target_tex, iuv, vec4(vec3(debug_col.r), 1.0));
}
