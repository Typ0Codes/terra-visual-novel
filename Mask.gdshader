shader_type canvas_item;

uniform sampler2D image_texture : source_color;
uniform vec4 mask_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform float tolerance = 0.3;





void fragment() {
	
    vec4 mask_pixel = texture(TEXTURE, UV);
    float diff = length(abs(mask_pixel.rgb - mask_color.rgb));

    if (diff <= tolerance) {
        COLOR = texture(image_texture, UV);
    } else {
        discard;
    }
}