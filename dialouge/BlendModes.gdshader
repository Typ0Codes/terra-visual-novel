shader_type canvas_item;

// This grabs whatever is rendered behind the current node on the screen
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Dropdown menu expanded with the new Smart Legible mode
uniform int blend_mode : hint_enum(
	"Normal:0", 
	"Multiply:1", 
	"Screen:2", 
	"Overlay:3", 
	"Darken:4", 
	"Lighten:5", 
	"Color Dodge:6", 
	"Color Burn:7", 
	"Hard Light:8", 
	"Soft Light:9", 
	"Difference:10", 
	"Exclusion:11",
	"Subtract:12",
	"Divide:13",
	"Addition:14",
	"Grain Extract:15",
	"Grain Merge:16",
	"Invert:17",
	"Smart Legible:18"
) = 0;

// --- GIMP BLEND MODE FUNCTIONS ---

vec3 blend_normal(vec3 base, vec3 blend) {
	return blend;
}

vec3 blend_multiply(vec3 base, vec3 blend) {
	return base * blend;
}

vec3 blend_screen(vec3 base, vec3 blend) {
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

vec3 blend_overlay(vec3 base, vec3 blend) {
	vec3 limit = step(vec3(0.5), base);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

vec3 blend_darken(vec3 base, vec3 blend) {
	return min(base, blend);
}

vec3 blend_lighten(vec3 base, vec3 blend) {
	return max(base, blend);
}

vec3 blend_color_dodge(vec3 base, vec3 blend) {
	return base / max(vec3(0.0001), 1.0 - blend);
}

vec3 blend_color_burn(vec3 base, vec3 blend) {
	return 1.0 - min(vec3(1.0), (1.0 - base) / max(vec3(0.0001), blend));
}

vec3 blend_hard_light(vec3 base, vec3 blend) {
	vec3 limit = step(vec3(0.5), blend);
	return mix(2.0 * base * blend, 1.0 - 2.0 * (1.0 - base) * (1.0 - blend), limit);
}

vec3 blend_soft_light(vec3 base, vec3 blend) {
	vec3 limit = step(vec3(0.5), blend);
	return mix(
		2.0 * base * blend + base * base * (1.0 - 2.0 * blend),
		sqrt(max(vec3(0.0), base)) * (2.0 * blend - 1.0) + (2.0 * base) * (1.0 - blend),
		limit
	);
}

vec3 blend_difference(vec3 base, vec3 blend) {
	return abs(base - blend);
}

vec3 blend_exclusion(vec3 base, vec3 blend) {
	return base + blend - 2.0 * base * blend;
}

vec3 blend_subtract(vec3 base, vec3 blend) {
	return max(vec3(0.0), base - blend);
}

vec3 blend_divide(vec3 base, vec3 blend) {
	return base / max(vec3(0.0001), blend);
}

vec3 blend_addition(vec3 base, vec3 blend) {
	return min(vec3(1.0), base + blend);
}

vec3 blend_grain_extract(vec3 base, vec3 blend) {
	return clamp(base - blend + vec3(0.5), vec3(0.0), vec3(1.0));
}

vec3 blend_grain_merge(vec3 base, vec3 blend) {
	return clamp(base + blend - vec3(0.5), vec3(0.0), vec3(1.0));
}

vec3 blend_invert(vec3 base, vec3 blend) {
	return 1.0 - base;
}

// Custom adaptive contrast mode designed specifically for UI text legibility
vec3 blend_smart_legible(vec3 base, vec3 blend) {
	// Calculate perceived luminance (brightness) of the background image
	float bg_luminance = dot(base, vec3(0.299, 0.587, 0.114));
	
	// If the background is bright (> 0.5), push text dark. If dark, push text bright.
	vec3 contrast_adjusted = (bg_luminance > 0.5) 
		? (base * 0.15 + (1.0 - blend) * 0.2) // Dark, crisp text for bright backgrounds
		: (base * 1.3 + blend * 0.9);         // Bright, popping text for dark backgrounds
		
	return clamp(contrast_adjusted, 0.0, 1.0);
}

void fragment() {
	// Base is what's behind the node on the screen
	vec4 background = texture(screen_texture, SCREEN_UV);
	
	// Font texture multiplied by COLOR to respect Label font colors
	vec4 sprite = texture(TEXTURE, UV) * COLOR;
	
	vec3 final_rgb = background.rgb;
	
	// Apply the chosen blend mode
	switch(blend_mode) {
		case 0:  final_rgb = blend_normal(background.rgb, sprite.rgb); break;
		case 1:  final_rgb = blend_multiply(background.rgb, sprite.rgb); break;
		case 2:  final_rgb = blend_screen(background.rgb, sprite.rgb); break;
		case 3:  final_rgb = blend_overlay(background.rgb, sprite.rgb); break;
		case 4:  final_rgb = blend_darken(background.rgb, sprite.rgb); break;
		case 5:  final_rgb = blend_lighten(background.rgb, sprite.rgb); break;
		case 6:  final_rgb = blend_color_dodge(background.rgb, sprite.rgb); break;
		case 7:  final_rgb = blend_color_burn(background.rgb, sprite.rgb); break;
		case 8:  final_rgb = blend_hard_light(background.rgb, sprite.rgb); break;
		case 9:  final_rgb = blend_soft_light(background.rgb, sprite.rgb); break;
		case 10: final_rgb = blend_difference(background.rgb, sprite.rgb); break;
		case 11: final_rgb = blend_exclusion(background.rgb, sprite.rgb); break;
		case 12: final_rgb = blend_subtract(background.rgb, sprite.rgb); break;
		case 13: final_rgb = blend_divide(background.rgb, sprite.rgb); break;
		case 14: final_rgb = blend_addition(background.rgb, sprite.rgb); break;
		case 15: final_rgb = blend_grain_extract(background.rgb, sprite.rgb); break;
		case 16: final_rgb = blend_grain_merge(background.rgb, sprite.rgb); break;
		case 17: final_rgb = blend_invert(background.rgb, sprite.rgb); break;
		case 18: final_rgb = blend_smart_legible(background.rgb, sprite.rgb); break;
	}
	
	// Smoothly mix back to the normal background where the text is transparent
	vec3 blended_rgb = mix(background.rgb, final_rgb, sprite.a);
	
	COLOR = vec4(blended_rgb, background.a);
}