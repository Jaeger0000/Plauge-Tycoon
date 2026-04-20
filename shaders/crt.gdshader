shader_type canvas_item;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.06;
uniform float scanline_frequency : hint_range(0.1, 20.0) = 3.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.12;
uniform float chromatic_aberration : hint_range(0.0, 2.0) = 0.3;
uniform float flicker_strength : hint_range(0.0, 0.2) = 0.008;
uniform float curvature : hint_range(0.0, 2.0) = 1.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 barrel_distort(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	float r2 = dot(centered, centered);
	centered *= 1.0 + curvature * 0.08 * r2;
	return centered * 0.5 + 0.5;
}

void fragment() {
	vec2 uv = barrel_distort(SCREEN_UV);

	float aberration = chromatic_aberration * 0.0015;
	float r = texture(SCREEN_TEXTURE, uv + vec2(aberration, 0.0)).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - vec2(aberration, 0.0)).b;
	vec3 color = vec3(r, g, b);

	float scanline = sin((SCREEN_UV.y * SCREEN_PIXEL_SIZE.y) * 2.0 * PI * scanline_frequency);
	color -= scanline_strength * 0.08 * scanline;

	float vignette = 1.0 - smoothstep(0.3, 1.15, length(SCREEN_UV - vec2(0.5)) * 1.2);
	color *= mix(1.0, vignette, vignette_strength);

	float flicker = (rand(vec2(TIME, SCREEN_UV.y * 120.0)) - 0.5) * flicker_strength;
	color += flicker;

	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
