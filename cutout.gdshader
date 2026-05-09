shader_type canvas_item;

uniform vec3 bg_color = vec3(0.07, 0.067, 0.063); // ~ (18,17,16) / 255
uniform float threshold : hint_range(0.0, 1.5) = 0.25;
uniform float softness : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = distance(c.rgb, bg_color);
	float a = smoothstep(threshold, threshold + softness, d);
	c.a *= a;
	COLOR = c;
}

