shader_type canvas_item;

// Planet warp (SPEC_planet P5). Inverse-polar remap of the composited world texture.
//
// The world is simulated in a rectangular grid W x H (x = angle around the planet, y =
// depth toward the core). This shader is run on a full-screen TextureRect (PlanetView)
// that samples the SubViewport composite (terrain + all Node2D overlays, rendered in
// grid space) and bends it into a disc: surface = outer rim, core = center.
//
// For every screen pixel we compute the world-space vector from the planet center, its
// radius r and angle theta, then map (theta, r) -> grid UV. r > r_surface = sky,
// r < r_inner = core blob (covers the central singularity). Matches PlanetCamera.gd.

uniform sampler2D world_tex : filter_nearest, repeat_enable;  // SubViewport composite (W x H)
uniform float view_angle = 0.0;              // camera angle offset (rad) - A/D rotates
uniform float view_radius_center = 0.0;      // radial centering (px) - W/S depth
uniform float view_zoom = 1.0;               // screen px per world px (1 = raw)
uniform float r_surface = 651.9;             // W / (2*PI)
uniform float r_inner = 203.9;               // R_surface - H (core blob radius)
uniform vec2  screen_size = vec2(1664.0, 960.0);
uniform vec3  core_color : source_color = vec3(0.16, 0.13, 0.11);   // core blob
uniform vec3  sky_color : source_color = vec3(0.02, 0.02, 0.05);    // space (r > r_surface)

// TAU is a built-in constant in the Godot shading language (2*PI).

void fragment() {
	// Reconstruct screen-pixel position from UV (PlanetView spans the whole window).
	vec2 screen_px = UV * screen_size;
	// Planet center placed so that radius r=view_radius_center sits at the screen center.
	vec2 planet_center = screen_size * 0.5 + vec2(0.0, view_radius_center * view_zoom);
	vec2 d = screen_px - planet_center;
	vec2 world_vec = d / max(view_zoom, 0.0001);
	float r = length(world_vec);
	float theta = atan(world_vec.y, world_vec.x) + view_angle;

	if (r > r_surface) {
		// Sky / space beyond the surface rim.
		COLOR = vec4(sky_color, 1.0);
	} else if (r < r_inner) {
		// Core blob: solid cap over the central singularity (no grid content here).
		COLOR = vec4(core_color, 1.0);
	} else {
		// Map polar -> grid UV. u = angle/TAU (wraps at the seam), v = depth (0 surface..1 core).
		float u = fract(theta / TAU);
		float span = max(r_surface - r_inner, 0.0001);   // = H
		float v = (r_surface - r) / span;
		COLOR = texture(world_tex, vec2(u, v));
	}
}
