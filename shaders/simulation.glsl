#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer GridData {
    uint cells[];
} grid;

layout(push_constant, std430) uniform Params {
    uint width;
    uint height;
    uint frame;
    uint pass_id;   // eri passi per dispatch
    uint pad0;
    uint grav_gun_x;      // Gravity gun kohde X (grid-koordinaatti)
    uint grav_gun_y;      // Gravity gun kohde Y
    uint grav_gun_mode;   // 0 = pois, 1 = veto
    uint grav_gun_radius; // Vetovoiman säde pikseleinä
} p;

const uint EMPTY = 0u;
const uint SAND  = 1u;
const uint WATER = 2u;
const uint STONE = 3u;
const uint WOOD  = 4u;
const uint FIRE  = 5u;
const uint OIL   = 6u;
const uint STEAM = 7u;
const uint ASH   = 8u;
const uint WOOD_FALLING = 9u;

uint get_mat(uint cell) { return cell & 0xFFu; }

uint hash(uint x) {
    x ^= x >> 17u;
    x *= 0xbf58476du;
    x ^= x >> 13u;
    x *= 0x94d049bbu;
    x ^= x >> 16u;
    return x;
}

bool falls(uint mat) {
    return mat == SAND || mat == WATER || mat == OIL || mat == ASH || mat == WOOD_FALLING;
}

bool is_liquid(uint mat) {
    return mat == WATER || mat == OIL;
}

bool is_powder(uint mat) {
    return mat == SAND || mat == ASH;
}

// Yritä siirtää solu src_idx -> dst_idx atomisesti
// Pyyhitään lähde ENSIN → estää duplikaation (vain yksi thread voi "poimia" solun)
bool try_atomic_move(uint src_idx, uint dst_idx, uint my_cell, uint expected_dst) {
    // 1. Poista lähteestä (varaa omistajuus)
    uint old_src = atomicCompSwap(grid.cells[src_idx], my_cell, expected_dst);
    if (old_src != my_cell) return false;  // Joku muu otti sen jo

    // 2. Kirjoita kohteeseen
    uint old_dst = atomicCompSwap(grid.cells[dst_idx], expected_dst, my_cell);
    if (old_dst == expected_dst) return true;  // Onnistui

    // 3. Kohde varattu — palauta lähde
    atomicCompSwap(grid.cells[src_idx], expected_dst, my_cell);
    return false;
}

// Yritä vaihtaa kaksi solua (esim. hiekka uppoaa veden läpi)
bool try_atomic_swap(uint src_idx, uint dst_idx, uint src_cell, uint dst_cell) {
    // Yritä ensin kirjoittaa src:n arvo dst:hen
    uint old_dst = atomicCompSwap(grid.cells[dst_idx], dst_cell, src_cell);
    if (old_dst == dst_cell) {
        // dst onnistui — kirjoita dst:n arvo src:hen
        atomicCompSwap(grid.cells[src_idx], src_cell, dst_cell);
        return true;
    }
    return false;
}

// Gravity gun: veto kohti kohdetta
bool try_gravity_gun(uint idx, uint x, uint y, uint my_cell) {
    int gx = int(p.grav_gun_x);
    int gy = int(p.grav_gun_y);
    int dx = gx - int(x);
    int dy = gy - int(y);
    int dist2 = dx * dx + dy * dy;
    int r = int(p.grav_gun_radius);

    if (dist2 > r * r || dist2 == 0) return false;

    // Pääsuunta + vaihtoehto
    int sx = (dx > 0) ? 1 : (dx < 0) ? -1 : 0;
    int sy = (dy > 0) ? 1 : (dy < 0) ? -1 : 0;

    uint my_mat = get_mat(my_cell);

    // Yritys 1: pääsuunta (pisin akseli)
    int mx = 0, my_ = 0;
    if (abs(dx) >= abs(dy)) { mx = sx; } else { my_ = sy; }
    {
        int nx = int(x) + mx;
        int ny = int(y) + my_;
        if (nx >= 0 && uint(nx) < p.width && ny >= 0 && uint(ny) < p.height) {
            uint di = uint(ny) * p.width + uint(nx);
            uint dc = grid.cells[di];
            uint dm = get_mat(dc);
            if (dm == EMPTY) return try_atomic_move(idx, di, my_cell, dc);
            if (is_powder(my_mat) && is_liquid(dm)) return try_atomic_swap(idx, di, my_cell, dc);
        }
    }
    // Yritys 2: diagonaali
    if (sx != 0 && sy != 0) {
        int nx = int(x) + sx;
        int ny = int(y) + sy;
        if (nx >= 0 && uint(nx) < p.width && ny >= 0 && uint(ny) < p.height) {
            uint di = uint(ny) * p.width + uint(nx);
            uint dc = grid.cells[di];
            uint dm = get_mat(dc);
            if (dm == EMPTY) return try_atomic_move(idx, di, my_cell, dc);
            if (is_powder(my_mat) && is_liquid(dm)) return try_atomic_swap(idx, di, my_cell, dc);
        }
    }
    // Yritys 3: sivuakseli
    {
        int ax = 0, ay = 0;
        if (abs(dx) >= abs(dy)) { ay = sy; } else { ax = sx; }
        if (ax != 0 || ay != 0) {
            int nx = int(x) + ax;
            int ny = int(y) + ay;
            if (nx >= 0 && uint(nx) < p.width && ny >= 0 && uint(ny) < p.height) {
                uint di = uint(ny) * p.width + uint(nx);
                uint dc = grid.cells[di];
                if (get_mat(dc) == EMPTY) return try_atomic_move(idx, di, my_cell, dc);
            }
        }
    }
    return false;
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint y = gl_GlobalInvocationID.y;

    if (x >= p.width || y >= p.height) return;

    uint idx = y * p.width + x;
    uint my_cell = grid.cells[idx];
    uint mat = get_mat(my_cell);

    // Staattiset ja tyhjät skipataan
    if (mat == EMPTY || mat == STONE || mat == WOOD) return;

    uint rng = hash(x * 374761393u + y * 668265263u + p.frame * 48271u + p.pass_id * 16807u);
    bool coin = (rng & 1u) != 0u;
    int dir = coin ? 1 : -1;

    uint max_x = p.width - 1u;
    uint max_y = p.height - 1u;

    // Gravity gun: veto — try_atomic_move korjattu, ei duplikaatiota
    if (p.grav_gun_mode == 1u && (falls(mat) || mat == FIRE || mat == STEAM)) {
        if (try_gravity_gun(idx, x, y, my_cell)) return;
    }

    // ========== JAUHE (hiekka, tuhka) ==========
    if (is_powder(mat)) {
        // Suoraan alas
        if (y < max_y) {
            uint below_idx = idx + p.width;
            uint below_cell = grid.cells[below_idx];
            uint below_mat = get_mat(below_cell);

            if (below_mat == EMPTY) {
                if (try_atomic_move(idx, below_idx, my_cell, below_cell)) return;
            }
            // Uppoa nesteen läpi
            if (below_mat == WATER || below_mat == OIL) {
                if (try_atomic_swap(idx, below_idx, my_cell, below_cell)) return;
            }
        }

        // Diagonaali alas
        for (int attempt = 0; attempt < 2; attempt++) {
            int dx = (attempt == 0) ? dir : -dir;
            uint nx = x + uint(dx);
            if (nx <= max_x && y < max_y) {
                uint diag_idx = (y + 1u) * p.width + nx;
                uint diag_cell = grid.cells[diag_idx];
                uint diag_mat = get_mat(diag_cell);
                if (diag_mat == EMPTY) {
                    if (try_atomic_move(idx, diag_idx, my_cell, diag_cell)) return;
                }
                if (diag_mat == WATER || diag_mat == OIL) {
                    if (try_atomic_swap(idx, diag_idx, my_cell, diag_cell)) return;
                }
            }
        }
        return;
    }

    // ========== PUTOAVA PUU ==========
    if (mat == WOOD_FALLING) {
        // Suoraan alas (vain tyhjään — ei uppoa nesteiden läpi)
        if (y < max_y) {
            uint below_idx = idx + p.width;
            uint below_cell = grid.cells[below_idx];
            uint below_mat = get_mat(below_cell);

            if (below_mat == EMPTY) {
                if (try_atomic_move(idx, below_idx, my_cell, below_cell)) return;
            }
        }

        // Diagonaali alas (vain tyhjään) — signed aritmetiikka
        for (int attempt = 0; attempt < 2; attempt++) {
            int dx = (attempt == 0) ? dir : -dir;
            int nx_s = int(x) + dx;
            if (nx_s >= 0 && uint(nx_s) <= max_x && y < max_y) {
                uint diag_idx = (y + 1u) * p.width + uint(nx_s);
                uint diag_cell = grid.cells[diag_idx];
                if (get_mat(diag_cell) == EMPTY) {
                    if (try_atomic_move(idx, diag_idx, my_cell, diag_cell)) return;
                }
            }
        }

        // Ei voinut liikkua mihinkään → laskeutunut, palaudu puuksi
        atomicCompSwap(grid.cells[idx], my_cell, (my_cell & 0xFFFFFF00u) | WOOD);
        return;
    }

    // ========== NESTE (vesi, öljy) ==========
    if (is_liquid(mat)) {
        // Alas
        if (y < max_y) {
            uint below_idx = idx + p.width;
            uint below_cell = grid.cells[below_idx];
            uint below_mat = get_mat(below_cell);
            if (below_mat == EMPTY) {
                if (try_atomic_move(idx, below_idx, my_cell, below_cell)) return;
            }
            // Öljy ei uppoa veden läpi (sama tiheys), mutta hiekka kyllä (handled above)
        }

        // Diag alas
        for (int attempt = 0; attempt < 2; attempt++) {
            int dx = (attempt == 0) ? dir : -dir;
            uint nx = x + uint(dx);
            if (nx <= max_x && y < max_y) {
                uint diag_idx = (y + 1u) * p.width + nx;
                uint diag_cell = grid.cells[diag_idx];
                if (get_mat(diag_cell) == EMPTY) {
                    if (try_atomic_move(idx, diag_idx, my_cell, diag_cell)) return;
                }
            }
        }

        // Sivulle (nesteet leviävät) — signed aritmetiikka uint-ylivuodon välttämiseksi
        uint spread = (mat == WATER) ? 3u : 2u;
        for (uint i = 1u; i <= spread; i++) {
            int nx_s = int(x) + dir * int(i);
            if (nx_s < 0 || uint(nx_s) > max_x) break;
            uint nx = uint(nx_s);
            uint side_idx = y * p.width + nx;
            uint side_cell = grid.cells[side_idx];
            if (get_mat(side_cell) == EMPTY) {
                if (try_atomic_move(idx, side_idx, my_cell, side_cell)) return;
            } else {
                break;
            }
        }
        for (uint i = 1u; i <= spread; i++) {
            int nx_s = int(x) - dir * int(i);
            if (nx_s < 0 || uint(nx_s) > max_x) break;
            uint nx = uint(nx_s);
            uint side_idx = y * p.width + nx;
            uint side_cell = grid.cells[side_idx];
            if (get_mat(side_cell) == EMPTY) {
                if (try_atomic_move(idx, side_idx, my_cell, side_cell)) return;
            } else {
                break;
            }
        }
        return;
    }

    // ========== TULI ==========
    if (mat == FIRE) {
        // Kuolema
        if ((rng % 25u) == 0u) {
            atomicCompSwap(grid.cells[idx], my_cell, 0u);
            return;
        }

        // Nousee ylöspäin
        if (y > 0u) {
            int fx = int(x) + int(rng % 3u) - 1;
            if (fx >= 0 && uint(fx) <= max_x) {
                uint up_idx = (y - 1u) * p.width + uint(fx);
                uint up_cell = grid.cells[up_idx];
                if (get_mat(up_cell) == EMPTY) {
                    try_atomic_move(idx, up_idx, my_cell, up_cell);
                }
            }
        }

        // Sytytä naapurit
        uint rng3 = hash(rng + 300u);
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int nx = int(x) + dx;
                int ny = int(y) + dy;
                if (nx >= 0 && uint(nx) <= max_x && ny >= 0 && uint(ny) <= max_y) {
                    uint nidx = uint(ny) * p.width + uint(nx);
                    uint ncell = grid.cells[nidx];
                    uint nmat = get_mat(ncell);

                    if ((nmat == WOOD || nmat == WOOD_FALLING) && (hash(rng3 + uint(dx + dy * 3)) % 50u) == 0u) {
                        atomicCompSwap(grid.cells[nidx], ncell, (ncell & 0xFFFFFF00u) | FIRE);
                    }
                    if (nmat == OIL && (hash(rng3 + uint(dx + dy * 3) + 100u) % 12u) == 0u) {
                        atomicCompSwap(grid.cells[nidx], ncell, (ncell & 0xFFFFFF00u) | FIRE);
                    }
                    if (nmat == WATER && (hash(rng3 + uint(dx + dy * 3) + 200u) % 8u) == 0u) {
                        // Vesi → höyry, tuli kuolee
                        atomicCompSwap(grid.cells[nidx], ncell, (ncell & 0xFFFFFF00u) | STEAM);
                        atomicCompSwap(grid.cells[idx], my_cell, 0u);
                        return;
                    }
                }
            }
        }

        // Tuli → tuhka
        if ((hash(rng + 600u) % 100u) == 0u) {
            atomicCompSwap(grid.cells[idx], my_cell, (my_cell & 0xFFFFFF00u) | ASH);
        }
        return;
    }

    // ========== HÖYRY ==========
    if (mat == STEAM) {
        // Katoaa
        if ((rng & 127u) == 0u) {
            atomicCompSwap(grid.cells[idx], my_cell, 0u);
            return;
        }

        // Nousee ylöspäin
        if (y > 0u) {
            int sx = int(x) + int(rng % 3u) - 1;
            if (sx >= 0 && uint(sx) <= max_x) {
                uint up_idx = (y - 1u) * p.width + uint(sx);
                uint up_cell = grid.cells[up_idx];
                if (get_mat(up_cell) == EMPTY) {
                    if (try_atomic_move(idx, up_idx, my_cell, up_cell)) return;
                }
            }
        }

        // Sivulle — signed aritmetiikka
        int snx_s = int(x) + dir;
        if (snx_s >= 0 && uint(snx_s) <= max_x) {
            uint side_idx = y * p.width + uint(snx_s);
            uint side_cell = grid.cells[side_idx];
            if (get_mat(side_cell) == EMPTY) {
                try_atomic_move(idx, side_idx, my_cell, side_cell);
            }
        }
        return;
    }
}
