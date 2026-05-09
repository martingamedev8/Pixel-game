shader_type canvas_item;

uniform float cutoff : hint_range(0.0, 1.0) = 0.18;
uniform float softness : hint_range(0.0, 0.5) = 0.06;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	float a = smoothstep(cutoff, cutoff + softness, luma);
	c.a *= a;
	COLOR = c;
}

