shader_type canvas_item;

// Väri-siemen tekstuuri
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform int frame;

// TEXTURE = grid data (R8, materiaali-ID per pikseli)
// Materiaalien värit
const vec3 MAT_COLORS[10] = {
	vec3(0.08, 0.08, 0.12),   // 0 EMPTY
	vec3(0.86, 0.78, 0.45),   // 1 SAND
	vec3(0.2, 0.4, 0.85),     // 2 WATER
	vec3(0.5, 0.5, 0.52),     // 3 STONE
	vec3(0.45, 0.28, 0.12),   // 4 WOOD
	vec3(1.0, 0.5, 0.1),      // 5 FIRE
	vec3(0.2, 0.15, 0.1),     // 6 OIL
	vec3(0.8, 0.85, 0.9),     // 7 STEAM
	vec3(0.35, 0.33, 0.3),    // 8 ASH
	vec3(0.45, 0.28, 0.12)    // 9 WOOD_FALLING (sama väri kuin WOOD)
};

const float MAT_VAR[10] = {
	0.0, 0.06, 0.04, 0.05, 0.04, 0.2, 0.02, 0.05, 0.03, 0.04
};

void fragment() {
	// Lue materiaali-ID tekstuurista
	float mat_raw = texture(TEXTURE, UV).r;
	int mat_id = clamp(int(mat_raw * 255.0 + 0.5), 0, 9);

	float seed_val = texture(seed_tex, UV).r;
	vec3 color = MAT_COLORS[mat_id];
	float variation = MAT_VAR[mat_id];

	// Värivariaatio
	float offset = (seed_val - 0.5) * 2.0 * variation;
	color.r = clamp(color.r + offset, 0.0, 1.0);
	color.g = clamp(color.g + offset * 0.8, 0.0, 1.0);
	color.b = clamp(color.b + offset * 0.6, 0.0, 1.0);

	// Tulen välke
	if (mat_id == 5) {
		float flicker = fract(sin(dot(UV * float(frame) * 3.7, vec2(12.9898, 78.233))) * 43758.5453);
		color.r = clamp(color.r + flicker * 0.3, 0.0, 1.0);
		color.g = clamp(color.g * (0.5 + flicker * 0.5), 0.0, 1.0);
		color.b = clamp(color.b * flicker * 0.3, 0.0, 1.0);
	}

	// Veden aaltoilu
	if (mat_id == 2) {
		float wave = sin(UV.x * 50.0 + float(frame) * 0.15) * 0.025;
		color.b = clamp(color.b + wave, 0.0, 1.0);
		color.g = clamp(color.g + wave * 0.5, 0.0, 1.0);
	}

	// Höyryn häive
	if (mat_id == 7) {
		color = mix(MAT_COLORS[0], color, 0.5 + seed_val * 0.4);
	}

	COLOR = vec4(color, 1.0);
}
