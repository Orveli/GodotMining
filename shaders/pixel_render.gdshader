shader_type canvas_item;

// Väri-siemen tekstuuri
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform int frame;

// Gravity gun (poistettu käytöstä — uniformit säilytetään yhteensopivuuden vuoksi, eivät tee mitään)
uniform vec2 grav_gun_uv;
uniform int grav_gun_active;
uniform float grav_gun_radius;
uniform float grav_fill_ratio : hint_range(0.0, 1.0) = 0.0;

// Räjähdysflash
uniform vec2 flash_uv;
uniform float flash_radius;
uniform float flash_intensity;

// Laseri (poistettu käytöstä)
uniform vec2 laser_start_uv;
uniform vec2 laser_end_uv;
uniform float laser_intensity;

// Screenshake-intensiteetti (trauma^2, 0-1)
uniform float shake_intensity = 0.0;

// Lokaali chromatic aberration — osumakohdan ympärillä
uniform vec2 impact_uv = vec2(0.5);
uniform float impact_intensity = 0.0;  // 0-1, häviää nopeasti
uniform int impact_type = 0;           // 0=luoti, 1=raketti, 2=hakku

// Kuvasuhde (leveys/korkeus), käytetään efekteissä (CA, grav gun, laser, flash)
uniform float screen_aspect = 1.778;

// TEXTURE = grid data (R8, materiaali-ID per pikseli)
// Materiaalien värit (indeksit 0-19, MAT_BEDROCK=19 mukana) — runtime-vaihdettava paletti
uniform vec3 mat_colors[20];
uniform float mat_var[20];

void fragment() {
	// Lue materiaali-ID suoraan (ei screen-wide CA)
	float mat_raw = texture(TEXTURE, UV).r;
	int mat_id = clamp(int(mat_raw * 255.0 + 0.5), 0, 19);

	float seed_val = texture(seed_tex, UV).r;
	vec3 color = mat_colors[mat_id];
	float variation = mat_var[mat_id];

	// Värivariaatio
	float offset = (seed_val - 0.5) * 2.0 * variation;
	color.r = clamp(color.r + offset, 0.0, 1.0);
	color.g = clamp(color.g + offset * 0.8, 0.0, 1.0);
	color.b = clamp(color.b + offset * 0.6, 0.0, 1.0);

	// Lokaali chromatic aberration — vain osumakohdan ympärillä
	if (impact_intensity > 0.01) {
		vec2 diff = UV - impact_uv;
		diff.x *= screen_aspect;
		float dist = length(diff);
		float ca_radius = (impact_type == 1) ? 0.18 : 0.10;  // raketti isompi
		float local_t = clamp(1.0 - dist / ca_radius, 0.0, 1.0);
		local_t = local_t * local_t;
		float ca_str = impact_intensity * local_t * 0.014;
		if (ca_str > 0.001) {
			vec2 ca_offset = (UV - impact_uv) * ca_str;
			float r_s = texture(TEXTURE, clamp(UV + ca_offset, vec2(0.0), vec2(1.0))).r;
			float b_s = texture(TEXTURE, clamp(UV - ca_offset, vec2(0.0), vec2(1.0))).r;
			int r_id = clamp(int(r_s * 255.0 + 0.5), 0, 19);
			int b_id = clamp(int(b_s * 255.0 + 0.5), 0, 19);
			color.r = mix(color.r, mat_colors[r_id].r, local_t * impact_intensity);
			color.b = mix(color.b, mat_colors[b_id].b, local_t * impact_intensity);
		}
		// Hakku: keltainen kipinävälähdys
		if (impact_type == 2 && local_t > 0.7) {
			color = mix(color, vec3(1.0, 0.9, 0.3), local_t * impact_intensity * 0.6);
		}
	}

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
		color = mix(mat_colors[0], color, 0.5 + seed_val * 0.4);
	}

	// Bedrock-efekti: hitaasti liikkuva diagonaalinen raitakuvio
	if (mat_id == 19) {
		float stripe = sin((UV.x + UV.y) * 800.0 + float(frame) * 0.3) * 0.5 + 0.5;
		color = mix(color, color * 0.6, stripe * 0.2);
	}

	// Räjähdysflash: valkoinen radiaalinen häive
	if (flash_intensity > 0.0) {
		vec2 flash_diff = UV - flash_uv;
		flash_diff.x *= screen_aspect;
		float flash_dist = length(flash_diff);
		if (flash_dist < flash_radius) {
			float fi = (1.0 - flash_dist / flash_radius) * flash_intensity;
			color = mix(color, vec3(1.0, 0.95, 0.8), fi * 0.8);
		}
	}

	// Gravity gun -efekti: sininen hehku (normaali) tai violetti pyörre (vakuumi)
	if (grav_gun_active >= 1) {
		vec2 diff = UV - grav_gun_uv;
		// Korjaa aspektisuhdetta
		diff.x *= screen_aspect;
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
				// Normaali veto: sininen → keltainen → punainen täyttöasteen mukaan
				vec3 grav_color = mix(vec3(0.15, 0.3, 0.8), vec3(1.0, 0.8, 0.1), smoothstep(0.0, 0.7, grav_fill_ratio));
				grav_color = mix(grav_color, vec3(1.0, 0.2, 0.1), smoothstep(0.6, 1.0, grav_fill_ratio));
				// Täynnä-varoitus: voimakkaampi pulssi
				float full_boost = (grav_fill_ratio > 0.9) ? 1.5 : 1.0;
				float intensity = t * 0.25 * full_boost;
				color += grav_color * intensity * pulse;
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
		pa.x *= screen_aspect;
		ba.x *= screen_aspect;
		float t_line = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
		vec2 closest = a * vec2(screen_aspect, 1.0) + ba * vec2(screen_aspect, 1.0) * t_line;
		vec2 p_corr = UV * vec2(screen_aspect, 1.0);
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



	// Vignette — aina päällä, vahvistuu shaken mukaan
	float vign_base = 0.35;
	float vign_shake = shake_intensity * 0.4;
	vec2 vign_uv = UV * (1.0 - UV.yx);
	float vign = vign_uv.x * vign_uv.y * 15.0;
	vign = clamp(pow(vign, vign_base + vign_shake), 0.0, 1.0);
	color *= vign;

	COLOR = vec4(color, 1.0);
}
