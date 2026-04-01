shader_type canvas_item;

// Väri-siemen tekstuuri
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform int frame;

// Gravity gun
uniform vec2 grav_gun_uv;     // UV-koordinaatti (0-1)
uniform int grav_gun_active;   // 0 tai 1
uniform float grav_gun_radius; // Säde UV-tilassa

// Räjähdysflash
uniform vec2 flash_uv;
uniform float flash_radius;
uniform float flash_intensity;

// Laseri
uniform vec2 laser_start_uv;
uniform vec2 laser_end_uv;
uniform float laser_intensity;

// Pelaaja
uniform vec2 player_pos;        // UV-koordinaatti (vasen yläkulma)
uniform vec2 player_size;       // UV-koko
uniform int player_facing_right; // 1 = oikea, 0 = vasen
uniform int player_in_water;     // 1 = vedessä

// TEXTURE = grid data (R8, materiaali-ID per pikseli)
// Materiaalien värit
const vec3 MAT_COLORS[16] = {
	vec3(0.08, 0.08, 0.12),   // 0 EMPTY
	vec3(0.86, 0.78, 0.45),   // 1 SAND
	vec3(0.2, 0.4, 0.85),     // 2 WATER
	vec3(0.5, 0.5, 0.52),     // 3 STONE
	vec3(0.45, 0.28, 0.12),   // 4 WOOD
	vec3(1.0, 0.5, 0.1),      // 5 FIRE
	vec3(0.2, 0.15, 0.1),     // 6 OIL
	vec3(0.8, 0.85, 0.9),     // 7 STEAM
	vec3(0.35, 0.33, 0.3),    // 8 ASH
	vec3(0.45, 0.28, 0.12),   // 9 WOOD_FALLING (sama väri kuin WOOD)
	vec3(0.65, 0.88, 0.84),   // 10 GLASS
	vec3(0.45, 0.32, 0.18),   // 11 DIRT (tumma ruskea)
	vec3(0.55, 0.42, 0.38),   // 12 IRON_ORE (ruosteenpunainen)
	vec3(0.72, 0.65, 0.25),   // 13 GOLD_ORE (kellertava)
	vec3(0.68, 0.68, 0.72),   // 14 IRON (hopea)
	vec3(0.90, 0.78, 0.20)    // 15 GOLD (kultainen)
};

const float MAT_VAR[16] = {
	0.0, 0.06, 0.04, 0.05, 0.04, 0.2, 0.02, 0.05, 0.03, 0.04, 0.03,
	0.03, 0.04, 0.04, 0.02, 0.02
};

void fragment() {
	// Lue materiaali-ID tekstuurista
	float mat_raw = texture(TEXTURE, UV).r;
	int mat_id = clamp(int(mat_raw * 255.0 + 0.5), 0, 15);

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

	// Räjähdysflash: valkoinen radiaalinen häive
	if (flash_intensity > 0.0) {
		vec2 flash_diff = UV - flash_uv;
		flash_diff.x *= 1.778;
		float flash_dist = length(flash_diff);
		if (flash_dist < flash_radius) {
			float fi = (1.0 - flash_dist / flash_radius) * flash_intensity;
			color = mix(color, vec3(1.0, 0.95, 0.8), fi * 0.8);
		}
	}

	// Gravity gun -efekti: sininen hehku (normaali) tai violetti pyörre (vakuumi)
	if (grav_gun_active >= 1) {
		vec2 diff = UV - grav_gun_uv;
		// Korjaa aspektisuhdetta (640/360 ≈ 1.78)
		diff.x *= 1.778;
		float dist = length(diff);
		float r = grav_gun_radius;
		if (dist < r) {
			float t = 1.0 - dist / r;
			float pulse = 0.8 + 0.2 * sin(float(frame) * 0.3);

			if (grav_gun_active == 2) {
				// Vakuumimoodi: violetti pyörre, vahvempi efekti
				float intensity = t * 0.4;
				// Spiraalinen kierre
				float angle = atan(diff.y, diff.x);
				float spiral = sin(angle * 3.0 - float(frame) * 0.5 + dist * 20.0) * 0.5 + 0.5;
				intensity *= (0.7 + 0.3 * spiral);
				color += vec3(0.6, 0.15, 0.8) * intensity * pulse;
				// Reunaviiva
				if (t < 0.15) {
					color += vec3(0.8, 0.3, 1.0) * (t / 0.15) * 0.3;
				}
			} else {
				// Normaali veto: sininen hehku
				float intensity = t * 0.25;
				color += vec3(0.15, 0.3, 0.8) * intensity * pulse;
			}
		}
	}

	// Laseri-efekti: kirkas viiva A→B
	if (laser_intensity > 0.0) {
		// Etäisyys pisteestä viivalle (UV-tilassa, aspektikorjaus)
		vec2 a = laser_start_uv;
		vec2 b = laser_end_uv;
		vec2 pa = UV - a;
		vec2 ba = b - a;
		// Aspektikorjaus
		pa.x *= 1.778;
		ba.x *= 1.778;
		float t_line = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		vec2 closest = a * vec2(1.778, 1.0) + ba * vec2(1.778, 1.0) * t_line;
		vec2 p_corr = UV * vec2(1.778, 1.0);
		float line_dist = length(p_corr - closest);

		float beam_width = 0.008;  // Paksuus UV-tilassa
		if (line_dist < beam_width) {
			float d = line_dist / beam_width;
			// Ydin: kirkas valkoinen
			if (d < 0.3) {
				float core = (1.0 - d / 0.3) * laser_intensity;
				color = mix(color, vec3(1.0, 1.0, 1.0), core * 0.95);
			}
			// Keskivyöhyke: punainen/oranssi
			else if (d < 0.7) {
				float mid = (1.0 - (d - 0.3) / 0.4) * laser_intensity;
				color = mix(color, vec3(1.0, 0.3, 0.1), mid * 0.7);
			}
			// Ulkoreuna: haalea punainen glow
			else {
				float edge = (1.0 - (d - 0.7) / 0.3) * laser_intensity;
				color += vec3(1.0, 0.15, 0.05) * edge * 0.4;
			}
		}
	}

	// Pelaaja-renderöinti (pikseligrafiikka)
	if (player_size.x > 0.0 && player_size.y > 0.0) {
		vec2 p_rel = (UV - player_pos) / player_size;
		if (p_rel.x >= 0.0 && p_rel.x < 1.0 && p_rel.y >= 0.0 && p_rel.y < 1.0) {
			int px = int(p_rel.x * 4.0);
			int py = int(p_rel.y * 7.0);
			// Peilaus suunnan mukaan
			int sx = (player_facing_right == 1) ? px : (3 - px);

			// Sprite-data: 7 riviä, 4 pikseliä per rivi
			// Koodattu valmiiksi (2 bittiä per pikseli, pakattu inttiin)
			int row_data = 0;
			if (py == 0) row_data = 36;       // 0,2,2,0 = (0<<6)|(2<<4)|(2<<2)|0
			else if (py == 1) row_data = 36;  // 0,2,2,0
			else if (py == 2) row_data = 85;  // 1,1,1,1 = (1<<6)|(1<<4)|(1<<2)|1
			else if (py == 3) row_data = 20;  // 0,1,1,0 = (0<<6)|(1<<4)|(1<<2)|0
			else if (py == 4) row_data = 20;  // 0,1,1,0
			else if (py == 5) row_data = 60;  // 0,3,3,0 = (0<<6)|(3<<4)|(3<<2)|0
			else if (py == 6) row_data = 195; // 3,0,0,3 = (3<<6)|(0<<4)|(0<<2)|3

			int pixel_type = (row_data >> (sx * 2)) & 3;

			if (pixel_type > 0) {
				vec3 player_color;
				if (pixel_type == 1) {
					player_color = vec3(0.2, 0.55, 0.9);   // Vartalo (sininen)
				} else if (pixel_type == 2) {
					player_color = vec3(0.9, 0.75, 0.55);  // Pää (iho)
				} else {
					player_color = vec3(0.3, 0.2, 0.5);    // Jalat (tumma violetti)
				}
				// Vedessä tummennus
				if (player_in_water == 1) {
					player_color *= 0.7;
					player_color.b += 0.1;
				}
				color = player_color;
			}
		}
	}

	COLOR = vec4(color, 1.0);
}
