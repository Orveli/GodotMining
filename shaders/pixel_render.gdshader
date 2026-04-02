shader_type canvas_item;

// Väri-siemen tekstuuri
uniform sampler2D seed_tex : filter_nearest, repeat_disable;
uniform int frame;

// Gravity gun
uniform vec2 grav_gun_uv;     // UV-koordinaatti (0-1)
uniform int grav_gun_active;   // 0 tai 1
uniform float grav_gun_radius; // Säde UV-tilassa
uniform float grav_fill_ratio : hint_range(0.0, 1.0) = 0.0; // Täyttöaste 0–1

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

// Screenshake-intensiteetti (trauma^2, 0-1)
uniform float shake_intensity = 0.0;

// Lokaali chromatic aberration — osumakohdan ympärillä
uniform vec2 impact_uv = vec2(0.5);
uniform float impact_intensity = 0.0;  // 0-1, häviää nopeasti
uniform int impact_type = 0;           // 0=luoti, 1=raketti, 2=hakku

// Projektiilivalaistus
uniform vec2 proj_pos[8];
uniform float proj_type[8];  // 0.0=luoti, 1.0=raketti
uniform int proj_count = 0;

// Buried darkness — syvyyspohjainen pimeys
uniform int darkness_mode = 0;  // 0=pois, 1=päällä (O-näppäin)
uniform float screen_aspect = 1.778;  // Kuvasuhde (leveys/korkeus), asetetaan GDScriptistä
uniform float surface_y_norm = 0.40;  // Pinnan sijainti UV-tilassa

// Sky-visibility tekstuuri — BFS-pohjainen taivaasvalo
uniform sampler2D visibility_tex : filter_linear, repeat_disable;

// Day/night sykli
uniform float time_of_day = 0.5;  // 0=yö, 0.25=aamu, 0.5=päivä, 0.75=ilta

// Static pistemaalivalolähteet
uniform vec2 static_light_pos[8];
uniform vec3 static_light_color[8];
uniform float static_light_radius[8];
uniform int static_light_count = 0;

// TEXTURE = grid data (R8, materiaali-ID per pikseli)
// Materiaalien värit (indeksit 0-18, MAT_GRAVEL=18 mukana) — runtime-vaihdettava paletti
uniform vec3 mat_colors[19];
uniform float mat_var[19];

void fragment() {
	// Lue materiaali-ID suoraan (ei screen-wide CA)
	float mat_raw = texture(TEXTURE, UV).r;
	int mat_id = clamp(int(mat_raw * 255.0 + 0.5), 0, 18);

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
			int r_id = clamp(int(r_s * 255.0 + 0.5), 0, 18);
			int b_id = clamp(int(b_s * 255.0 + 0.5), 0, 18);
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

	// Pelaaja-renderöinti (pikseligrafiikka)
	bool player_drawn = false;
	if (player_size.x > 0.0 && player_size.y > 0.0) {
		vec2 p_rel = (UV - player_pos) / player_size;
		if (p_rel.x >= 0.0 && p_rel.x < 1.0 && p_rel.y >= 0.0 && p_rel.y < 1.0) {
			int px = int(p_rel.x * 6.0);
			int py = int(p_rel.y * 10.0);
			// Peilaus suunnan mukaan
			int sx = (player_facing_right == 1) ? px : (5 - px);

			// Sprite-data: 10 riviä, 6 pikseliä per rivi
			// Koodattu valmiiksi (2 bittiä per pikseli, pakattu inttiin)
			int row_data = 0;
			if      (py == 0) row_data = 160;  // 0,0,2,2,0,0
			else if (py == 1) row_data = 680;  // 0,2,2,2,2,0
			else if (py == 2) row_data = 680;  // 0,2,2,2,2,0
			else if (py == 3) row_data = 1365; // 1,1,1,1,1,1
			else if (py == 4) row_data = 340;  // 0,1,1,1,1,0
			else if (py == 5) row_data = 340;  // 0,1,1,1,1,0
			else if (py == 6) row_data = 340;  // 0,1,1,1,1,0
			else if (py == 7) row_data = 500;  // 0,1,3,3,1,0
			else if (py == 8) row_data = 1020; // 0,3,3,3,3,0
			else if (py == 9) row_data = 3855; // 3,3,0,0,3,3

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
				player_drawn = true;
			}
		}
	}


	// Projektiilivalaistus — raketit ja ammukset valaisevat ympäristön
	for (int i = 0; i < proj_count; i++) {
		vec2 diff = UV - proj_pos[i];
		diff.x *= screen_aspect;
		float dist = length(diff);
		float is_rocket = proj_type[i];
		float radius = mix(0.05, 0.15, is_rocket);
		if (dist < radius) {
			float t = 1.0 - dist / radius;
			t = t * t;
			// Luoti: kylmä valkoinen, raketti: lämmin oranssi
			vec3 light = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.55, 0.1), is_rocket);
			float brightness = mix(0.12, 0.45, is_rocket);
			color += light * t * brightness;
		}
	}

	// Vignette — aina päällä, vahvistuu shaken mukaan
	float vign_base = 0.35;
	float vign_shake = shake_intensity * 0.4;
	vec2 vign_uv = UV * (1.0 - UV.yx);
	float vign = vign_uv.x * vign_uv.y * 15.0;
	vign = clamp(pow(vign, vign_base + vign_shake), 0.0, 1.0);
	color *= vign;

	// === VALAISTUSSYSTEEMI (darkness_mode=1 aktivoi) ===
	if (darkness_mode == 1) {
		// --- Taivasvalo BFS-kartasta ---
		float vis_raw = texture(visibility_tex, UV).r;
		float sky_dist = vis_raw * 255.0;
		float sky_reach = clamp(1.0 - sky_dist / 250.0, 0.0, 1.0);
		sky_reach = sky_reach * sky_reach;

		// Epäsymmetrinen päivä/yö: 85% päivää, 15% yötä
		// time_of_day: 0=puoliöö, 0.5=keskipäivä
		float dist_mid = min(time_of_day, 1.0 - time_of_day);  // 0=puoliöö, 0.5=keskipäivä
		const float NIGHT_HALF = 0.075;  // 7.5% kummallakin puolella = 15% yö yhteensä
		float day_t = clamp((dist_mid - NIGHT_HALF) / (0.5 - NIGHT_HALF), 0.0, 1.0);
		float sun_intensity = mix(0.20, 1.0, day_t * day_t);

		// Taivasväri: yö → hämärä → päivä
		vec3 sky_noon  = vec3(1.0, 0.97, 0.85);
		vec3 sky_dusk  = vec3(1.0, 0.55, 0.2);
		vec3 sky_night = vec3(0.15, 0.2, 0.45);
		float twilight_t = clamp(smoothstep(0.0, 0.25, day_t) - smoothstep(0.25, 0.6, day_t), 0.0, 1.0);
		vec3 sky_color_tod = mix(sky_night, sky_noon, day_t * day_t);
		sky_color_tod = mix(sky_color_tod, sky_dusk, twilight_t * 0.9);

		float sky_light = sky_reach * sun_intensity;

		// --- Static pistemaalivalolähteet ---
		float point_light_total = 0.0;
		vec3 point_color_total = vec3(0.0);
		for (int i = 0; i < static_light_count; i++) {
			vec2 diff = UV - static_light_pos[i];
			diff.x *= screen_aspect;
			float dist_l = length(diff);
			float r = static_light_radius[i];
			if (dist_l < r) {
				float t = 1.0 - dist_l / r;
				t = t * t * t;
				point_light_total += t;
				point_color_total += static_light_color[i] * t;
			}
		}
		point_light_total = clamp(point_light_total, 0.0, 1.0);

		// --- Otsalamppu: V-muotoinen valokeila pelaajan päästä ---
		float headlamp = 0.0;
		if (player_size.x > 0.0) {
			// Pään sijainti: pelaajan yläosa keskellä
			vec2 head_uv = player_pos + vec2(player_size.x * 0.5, player_size.y * 0.1);
			vec2 to_px = UV - head_uv;
			to_px.x *= screen_aspect;
			float lamp_dist = length(to_px);
			// Suunta johon pelaaja katsoo
			float facing = (player_facing_right == 1) ? 1.0 : -1.0;
			vec2 facing_dir = vec2(facing, -0.1);  // Hieman alas suunnattu
			// Kulma keilaukseen: cos(50°) ≈ 0.643, laaja V
			float cone_cos = 0.60;
			float dot_f = dot(normalize(to_px), normalize(facing_dir));
			float cone_t = clamp((dot_f - cone_cos) / (1.0 - cone_cos), 0.0, 1.0);
			cone_t = cone_t * cone_t;
			// Etäisyysvaimeneminen — ulottuu noin 300px
			float lamp_radius = 300.0 / float(1664);
			float dist_t = clamp(1.0 - lamp_dist / lamp_radius, 0.0, 1.0);
			dist_t = dist_t * dist_t;
			headlamp = cone_t * dist_t * 0.75;
		}

		// --- Yhdistä ---
		float ambient = 0.12;
		float total_light = clamp(sky_light + point_light_total + headlamp + ambient, 0.0, 1.0);
		vec3 light_tint = mix(vec3(1.0), sky_color_tod, sky_light / max(total_light, 0.001));
		if (point_light_total > 0.001) {
			vec3 norm_point = point_color_total / max(point_light_total, 0.001);
			light_tint = mix(light_tint, norm_point, clamp(point_light_total * 0.6, 0.0, 1.0));
		}
		// Otsalamppu: kylmä valkoinen hehku
		if (headlamp > 0.001) {
			light_tint = mix(light_tint, vec3(0.9, 0.92, 1.0), headlamp * 0.4);
		}
		color *= total_light * light_tint;
	}

	COLOR = vec4(color, 1.0);
}
