shader_type canvas_item;
uniform sampler2D tex : source_color, filter_nearest;
uniform vec2 sprite_res = vec2(64.0, 64.0); // pixel grid for the sprite
uniform int color_bit_depth = 4;
uniform float dither_strength = 0.03;
uniform float jitter_amount = 0.008;
uniform float jitter_speed = 1.2;
uniform float jitter_frequency = 180.0;
uniform float chromatic_aberration_strength : hint_range(0.0, 0.1) = 0.015;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.8;
uniform float vignette_radius : hint_range(0.0, 2.0) = 0.9;

float hash(vec2 p){
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 psx_jitter(vec2 uv){
    float t = floor(TIME * jitter_speed * 8.0) / 8.0;
    float h = (hash(vec2(floor(uv.y * jitter_frequency), t)) - 0.5) * jitter_amount * 0.75;
    float v = (hash(vec2(floor(uv.x * jitter_frequency * 0.4), t)) - 0.5) * jitter_amount * 0.35;
    float m = (hash(uv * 600.0 + t) - 0.5) * jitter_amount * 0.1;
    return uv + vec2(h + m, v + m);
}

void fragment(){
    vec2 uv = floor(UV * sprite_res) / sprite_res + 0.5 / sprite_res;
    uv = psx_jitter(uv);

    vec2 off = (uv - 0.5) * chromatic_aberration_strength;
    vec4 c  = texture(TEXTURE, uv);
    vec3 col = vec3(
        texture(TEXTURE, uv + off).r,
        c.g,
        texture(TEXTURE, uv - off).b
    );

    float levels = pow(2.0, float(color_bit_depth));
    col = floor(col * levels) / levels;

    float dist = distance(SCREEN_UV, vec2(0.5));
    col *= 1.0 - vignette_strength * smoothstep(vignette_radius * 0.5, vignette_radius, dist);

    col += (hash(SCREEN_UV * 80.0 + floor(TIME * 50.0)) - 0.5) * dither_strength;

    COLOR = vec4(col, c.a); // keeps transparency
}