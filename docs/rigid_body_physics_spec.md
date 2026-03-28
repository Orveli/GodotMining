# GodotMining: Hybrid Rigid Body Physics — Technical Specification

**Author:** Game Architect
**Date:** 2026-03-28
**Status:** DESIGN — Not yet implemented

---

## 1. Executive Summary

This document specifies a **hybrid cellular automata + rigid body physics system** for GodotMining. The design is heavily inspired by Noita's approach (as described in their GDC 2019 talk): pixel-level materials run on the GPU as cellular automata, while rigid bodies are tracked on the CPU with shapes derived from the pixel data.

**Key goals:**
- Stone becomes a rigid body: gravity, rotation, center of mass, collision
- Stone can be CUT into pieces; each piece becomes its own rigid body
- Loose wood pixels fall like sand when disconnected from a structure
- All existing CA materials (sand, water, fire, etc.) continue working unchanged
- Real-time performance at 320x180

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                     Per-Frame Pipeline                     │
│                                                            │
│  1. GPU: Margolus CA simulation (6 passes) — sand/water/etc│
│     - Rigid body pixels are FROZEN (skipped by shader)     │
│                                                            │
│  2. CPU: Download grid from GPU                            │
│                                                            │
│  3. CPU: Rigid Body Physics Step                           │
│     a. Apply gravity + forces to each body                 │
│     b. Integrate velocity → new position/rotation          │
│     c. Collision detection (body↔body, body↔static grid)   │
│     d. Resolve collisions                                  │
│                                                            │
│  4. CPU: Rasterize rigid bodies back into the grid         │
│     - Erase old pixels, write new pixels at rotated pos    │
│                                                            │
│  5. CPU: Damage/cut detection → re-run CCL if needed       │
│                                                            │
│  6. CPU: Upload modified grid to GPU                       │
│                                                            │
│  7. GPU: Render (pixel_render.gdshader)                    │
└──────────────────────────────────────────────────────────┘
```

### Why CPU for rigid bodies?

- 320x180 = 57,600 pixels total. At most ~50-100 rigid bodies expected.
- Rigid body physics is inherently sequential (collision resolution, constraint solving).
- Connected component labeling on 57K pixels is trivial on CPU (<1ms).
- Noita also runs rigid bodies on CPU (Box2D) while pixels run on GPU/multithreaded.
- Godot's built-in physics is overkill and would fight our pixel grid; custom is simpler.

---

## 3. Data Structures

### 3.1 Cell Format Change

Current: `uint32 = (color_seed << 8) | material_id`

New: `uint32 = (body_id << 16) | (color_seed << 8) | material_id`

```
Bits  0-7:   material_id (0-255)
Bits  8-15:  color_seed (0-255)
Bits 16-31:  body_id (0 = no body / CA pixel, 1-65535 = rigid body ID)
```

This means a pixel that belongs to rigid body #42 stores `(42 << 16) | (seed << 8) | MAT_STONE`.

**Impact:** The shader already reads `cell & 0xFF` for material — unchanged. The body_id is invisible to the CA shader. The render shader also reads only the material byte — unchanged.

### 3.2 RigidBodyData (CPU-side, GDScript class)

```gdscript
class_name RigidBodyData

# Identiteetti
var body_id: int                    # 1-65535, vastaa body_id kenttiä gridissä
var material: int                   # MAT_STONE, MAT_WOOD, jne.

# Muoto — pikselit suhteessa painopisteeseen
# Array of Vector2i: offset from center of mass (local coords)
var local_pixels: Array[Vector2i]   # esim. [(-2,-1), (-1,-1), (0,-1), ...]

# Fysiikka
var position: Vector2               # Painopisteen sijainti maailmassa (float, subpixel)
var velocity: Vector2               # Nopeus pikseleinä/frame
var angle: float                    # Kiertymä radiaaneissa
var angular_velocity: float         # Kiertymänopeus rad/frame
var mass: float                     # = local_pixels.size()

# Johdetut
var bbox: Rect2i                    # Axis-aligned bounding box (maailmakoordinaatit)
var collision_polygon: PackedVector2Array  # Marching squares → Douglas-Peucker

# Tila
var is_sleeping: bool               # Ei liikkunut N framea → nuku
var sleep_counter: int
var is_static: bool                 # Ikuisesti paikallaan (esim. maanpohja)
```

### 3.3 PhysicsWorld (CPU-side manager)

```gdscript
class_name PhysicsWorld

var bodies: Dictionary              # body_id → RigidBodyData
var next_body_id: int = 1
var gravity: Vector2 = Vector2(0, 0.5)  # pikseliä/frame²

# Collision grid — bitmask/ID per cell, päivitetään joka frame
# Tätä käytetään nopeaan "onko tässä pikselissä jotain" -kyselyyn
var collision_grid: PackedInt32Array  # TOTAL kokoinen, body_id tai 0
```

### 3.4 Wood Connectivity (simplified)

Wood does NOT become a rigid body. Instead, we add a simpler system:
- **Connected wood** = any wood pixel touching another wood pixel (4-connected) that eventually connects to a "support" (stone, ground, or another rigid body).
- **Unsupported wood** = wood pixels not connected to any support → material behavior changes to "falling" (like sand).

This avoids the complexity of making wood rigid bodies while giving the desired "loose wood falls" behavior.

---

## 4. Algorithm Details

### 4.1 Connected Component Labeling (CCL) — Stone Body Detection

**When triggered:**
- On game start (initial scan)
- When a stone pixel is destroyed (fire, explosion, player action)
- When stone is painted by the player
- NOT every frame — only on damage events

**Algorithm: Two-pass Union-Find (CPU)**

```
Vaihe 1 — Ensimmäinen läpikäynti (first pass):
  For each pixel (x, y) where material == STONE:
    If left neighbor is STONE: union(this, left)
    If above neighbor is STONE: union(this, above)

Vaihe 2 — Toinen läpikäynti (second pass):
  For each pixel where material == STONE:
    root = find(this)
    Assign body_id based on root → body_id mapping

Vaihe 3 — Luo RigidBodyData jokaiselle komponentille:
  For each unique root:
    Collect all pixels
    Calculate center of mass = average of all pixel positions
    Convert to local coordinates (relative to CoM)
    Calculate mass = pixel count
    Generate collision polygon (marching squares)
```

**Performance:** 320x180 = 57,600 pixels. Union-find with path compression runs in effectively O(n). Expected time: <0.5ms.

### 4.2 Rigid Body Physics Step

Each frame, for each non-sleeping body:

```
Vaihe 1 — Voimat:
  velocity += gravity
  angular_velocity *= 0.99  # vaimennusta

Vaihe 2 — Integrointi:
  new_position = position + velocity
  new_angle = angle + angular_velocity

Vaihe 3 — Törmäystarkistus (collision detection):
  For each pixel in body (transformed by new_position + new_angle):
    world_pos = rotate(local_pixel, new_angle) + new_position
    Round to grid coordinates
    Check if grid cell is occupied by:
      a) Another rigid body → body-body collision
      b) A non-empty CA pixel (sand, water, stone powder) → body-grid collision
      c) Out of bounds → wall collision

Vaihe 4 — Törmäysvaste (collision response):
  If collision detected:
    Binary search for exact collision time (or step back)
    Calculate collision normal from overlapping pixels
    Apply impulse: reflect velocity along normal, apply friction
    For body-body: distribute impulse by mass ratio
    If body barely moving → increment sleep_counter

Vaihe 5 — Nukahdus (sleep):
  If |velocity| < 0.01 and |angular_velocity| < 0.001 for 30 frames:
    is_sleeping = true
    Snap to nearest integer position
    → Optionally "freeze" back into static grid (dissolve body)
```

### 4.3 Rasterization — Writing Bodies Back to Grid

Each frame, after physics:

```
Vaihe 1 — Poista vanhat pikselit:
  For each pixel in body.local_pixels:
    old_world = rotate(pixel, body.old_angle) + body.old_position
    grid[round(old_world)] = EMPTY  (if it still has our body_id)

Vaihe 2 — Kirjoita uudet pikselit:
  For each pixel in body.local_pixels:
    new_world = rotate(pixel, body.angle) + body.position
    ix, iy = round(new_world)
    If in bounds and grid[iy * W + ix] is EMPTY:
      grid[iy * W + ix] = material | (seed << 8) | (body_id << 16)
    Else:
      → Pixel lost (crushed) or collision needs resolving

Vaihe 3 — Rotation creates gaps:
  When rotating, some destination pixels may overlap and some source pixels
  may have no destination. We handle this by:
  - Allowing slight pixel count changes (lossy rotation)
  - OR using a "thick" rasterization that fills gaps
```

**Critical insight from Noita:** Each pixel "knows" its body_id and local offset. When the body moves, we compute the new world position from the local offset + body transform. This is robust against pixel-level destruction.

### 4.4 Cutting / Splitting a Rigid Body

When a pixel belonging to a rigid body is destroyed:

```
Vaihe 1 — Merkitse pikseli tuhotuksi:
  Remove pixel from body.local_pixels
  Set grid cell to EMPTY (or ASH, etc.)

Vaihe 2 — Tarkista yhteys (connectivity check):
  Run flood fill / BFS from any remaining pixel in the body
  If all pixels reached → body is still one piece, just update shape
  If NOT all pixels reached → body is split!

Vaihe 3 — Halkaise (split):
  For each connected component found:
    Create new RigidBodyData
    Recalculate center of mass, local_pixels, mass
    Inherit velocity + angular_velocity from parent body
    Generate new collision polygon
    Assign new body_id to grid pixels

Vaihe 4 — Pienimmät palaset → pikselimössöä:
  If a component has < MIN_BODY_SIZE (e.g., 4 pixels):
    Don't create a rigid body
    Convert to falling material (sand-like stone rubble)
    → New material: STONE_RUBBLE (id 9) or just use SAND behavior
```

### 4.5 Collision Polygon Generation (Marching Squares)

For body↔body collision and potentially future Godot physics integration:

```
Vaihe 1 — Marching Squares:
  Create a binary grid from body.local_pixels (1 = filled, 0 = empty)
  Run marching squares to extract contour line segments

Vaihe 2 — Douglas-Peucker simplification:
  Reduce vertex count (epsilon = 0.5 - 1.0 pixels)

Vaihe 3 — Store as PackedVector2Array:
  Used for SAT collision detection between bodies
  Regenerated only when body shape changes (cut/damage)
```

For the initial implementation, we can skip marching squares entirely and use **pixel-perfect collision** (check each pixel). At 320x180 with small bodies, this is fast enough. Marching squares is an optimization for later.

### 4.6 Wood Falling — Support Check

Every N frames (e.g., every 10 frames), or when wood/stone is destroyed nearby:

```
Vaihe 1 — Etsi tukipisteet (find support points):
  Support = any cell that is STONE, rigid body, or y == SIM_HEIGHT-1 (ground)

Vaihe 2 — Flood fill ylöspäin puussa (flood fill upward through wood):
  Start from every wood pixel adjacent to a support point
  Mark as "supported" using BFS/DFS through connected wood pixels

Vaihe 3 — Merkitse tuettomat (mark unsupported):
  Any wood pixel NOT reached by the flood fill:
    Change behavior to falling (treat like SAND in the shader)
    → Set a flag bit, or change material to MAT_WOOD_FALLING (new material 9)
```

**Alternative approach:** Add `MAT_WOOD_FALLING = 9` that behaves like sand in the compute shader but renders as wood. When a wood pixel lands and connects to support again, it reverts to `MAT_WOOD`.

---

## 5. Shader Modifications

### 5.1 simulation.glsl Changes

**Minimal changes needed:**

```glsl
// Uusi materiaalivakio
const uint WOOD_FALLING = 9u;

// falls() päivitetään
bool falls(uint mat) {
    return mat == SAND || mat == WATER || mat == OIL || mat == ASH || mat == WOOD_FALLING;
}

bool is_powder(uint mat) {
    return mat == SAND || mat == ASH || mat == WOOD_FALLING;
}

// Staattisten tarkistus — RIGID BODY PIKSELIT SKIPATAAN
// body_id > 0 tarkoittaa "tämä pikseli kuuluu rigid bodyyn"
uint get_body_id(uint cell) { return (cell >> 16u) & 0xFFFFu; }

void main() {
    // ... existing code ...
    uint my_cell = grid.cells[idx];
    uint mat = get_mat(my_cell);

    // Staattiset, tyhjät, JA rigid body -pikselit skipataan
    if (mat == EMPTY || mat == STONE || mat == WOOD) return;
    if (get_body_id(my_cell) != 0u) return;  // UUSI: kuuluu rigid bodyyn

    // ... rest of simulation unchanged ...
}
```

**Key insight:** Rigid body pixels are "frozen" in the CA simulation. The CPU moves them via rasterization. The CA shader never touches them. This is exactly how Noita does it.

### 5.2 pixel_render.gdshader Changes

```glsl
// Lisää uusi materiaali renderöintiin
const vec3 MAT_COLORS[10] = {
    // ... existing 9 ...
    vec3(0.45, 0.28, 0.12)   // 9 WOOD_FALLING (sama väri kuin WOOD)
};
```

No other render changes needed — body pixels look the same as regular stone/wood.

---

## 6. File Changes

### New Files

| File | Purpose |
|------|---------|
| `scripts/rigid_body_data.gd` | RigidBodyData class — yksittäisen kappaleen tiedot |
| `scripts/physics_world.gd` | PhysicsWorld — fysiikkamaailma, kaikki kappaleet, simulaatio |
| `scripts/ccl.gd` | Connected Component Labeling — Union-Find toteutus |
| `scripts/wood_support.gd` | Wood support/connectivity checker |
| `scripts/marching_squares.gd` | Marching squares contour extraction (Phase 3) |

### Modified Files

| File | Changes |
|------|---------|
| `shaders/simulation.glsl` | Skip rigid body pixels (`body_id > 0`), add `WOOD_FALLING`, update `falls()`/`is_powder()` |
| `shaders/pixel_render.gdshader` | Add color for `WOOD_FALLING` (material 9) |
| `scripts/pixel_world.gd` | Integrate PhysicsWorld into frame loop, modify grid upload/download for body_id bits, add cut tool |
| `scripts/ui.gd` | Add cut tool button, physics debug toggle |
| `scenes/main.tscn` | Possibly add debug visualization node |
| `CLAUDE.md` | Update material list, document new architecture |

---

## 7. pixel_world.gd Integration

The main game loop changes from:

```
_process():
  handle_input()
  upload_paint → GPU
  simulate_gpu() (6 passes)
  download_from_gpu()
  upload_render()
```

To:

```
_process():
  handle_input()
  upload_paint → GPU

  # Vaihe 1: CA-simulaatio (hiekka, vesi, tuli, jne.)
  simulate_gpu() (6 passes)
  download_from_gpu()

  # Vaihe 2: Rigid body -fysiikka (CPU)
  physics_world.step(grid, color_seed)
  # → Moves bodies, rasterizes into grid arrays

  # Vaihe 3: Tarkista puun tuki (joka 10. frame)
  if frame_count % 10 == 0:
    wood_support.check_and_convert(grid)

  # Vaihe 4: Tarkista onko rigid body -pikseleitä tuhottu
  physics_world.check_damage(grid)
  # → Runs CCL split if needed

  # Vaihe 5: Lataa muokattu grid GPU:lle
  upload_modified_to_gpu()  # tarvitaan koska CPU muutti gridiä

  upload_render()
```

**Performance note:** The extra GPU upload (`upload_modified_to_gpu`) is needed because the CPU modifies the grid (body rasterization, wood falling). This is 230KB — fast enough at 60fps.

---

## 8. Implementation Phases

### Phase 1: Wood Falling (simplest, high impact) — ~2 days

1. Add `MAT_WOOD_FALLING = 9` to both GDScript and GLSL
2. Update shader: `falls()` and `is_powder()` include `WOOD_FALLING`
3. Update render shader: color for material 9
4. Implement `wood_support.gd`: flood-fill connectivity check
5. In `pixel_world.gd`: every 10 frames, check wood support, convert unsupported → `WOOD_FALLING`
6. When `WOOD_FALLING` lands on solid ground/support, revert to `MAT_WOOD`

**Why first:** No rigid body complexity. Uses existing CA simulation. Immediately visible result.

### Phase 2: Static Rigid Bodies (stone tracking) — ~3 days

1. Implement `ccl.gd` with Union-Find
2. Implement `rigid_body_data.gd` class
3. Modify cell format: `body_id << 16` bits
4. On game start / stone paint: run CCL, create body records
5. Update shader: skip pixels with `body_id > 0`
6. Bodies exist but DON'T MOVE yet — just tracked and frozen

**Why second:** Sets up the data structures without physics complexity.

### Phase 3: Gravity and Movement — ~4 days

1. Implement `physics_world.gd` with gravity integration
2. Implement erase-old / write-new rasterization
3. Pixel-perfect collision with grid (no polygon needed yet)
4. Simple collision response: stop on contact, no rotation yet
5. Sleep detection

**Milestone:** Stone blocks fall and land on surfaces.

### Phase 4: Rotation and Center of Mass — ~3 days

1. Add rotation to physics integration
2. Implement rotated rasterization (rotate local_pixels around CoM)
3. Torque from off-center collisions
4. Handle pixel gaps from rotation (thick rasterization)

**Milestone:** Stone blocks tumble realistically.

### Phase 5: Cutting and Splitting — ~3 days

1. Add cut tool (line/click that destroys pixels)
2. On rigid body pixel destruction: BFS connectivity check
3. Split into multiple bodies if disconnected
4. Small fragments (<4 pixels) become powder/rubble
5. Recalculate mass, CoM, collision shape for each piece

**Milestone:** Player can cut stone and pieces fall independently.

### Phase 6: Polish and Optimization — ~2 days

1. Marching squares for collision polygons (optional)
2. Body-body collision (SAT or pixel-based)
3. Sleeping body optimization
4. Dissolve long-sleeping bodies back into static grid
5. Debug visualization (body outlines, CoM markers)

---

## 9. Risks and Mitigations

### Risk 1: Rotation causes pixel loss/duplication
**Problem:** When rotating a body, rounding to integer grid positions can cause pixels to overlap (two local pixels map to same world cell) or gaps (no local pixel maps to a world cell).
**Mitigation:** Accept minor pixel count changes. Use "conservative rasterization" — for each destination cell in the body's AABB, check if it's inside the body shape (inverse transform). This fills gaps at the cost of slight shape inflation. Noita also has this issue and accepts minor imprecision.

### Risk 2: GPU↔CPU sync overhead
**Problem:** Downloading the grid from GPU, modifying on CPU, uploading back adds latency.
**Mitigation:** At 320x180x4 = 230KB, this is well within PCIe bandwidth. Current code already does full download every frame. The extra upload for rigid body changes is another 230KB — negligible. If needed, we can upload only dirty regions.

### Risk 3: CCL performance on damage
**Problem:** Re-running full CCL every time a stone pixel is destroyed.
**Mitigation:** Only re-check the BODY that was damaged, not the entire grid. A body with 500 pixels can be BFS'd in <0.1ms. If the body has 5000+ pixels, we can amortize over multiple frames (mark as "needs recheck", process one body per frame).

### Risk 4: Body↔CA interaction (sand piling on rotating body)
**Problem:** Sand/water should pile up on rigid bodies, flow around them, etc.
**Mitigation:** The CA shader already skips rigid body pixels (they look "solid" to the CA). Sand will naturally pile on top. When a body moves, the rasterization clears old positions (→ EMPTY) and writes new positions. Sand above the old position may need a frame to fall into the gap, which looks natural.

### Risk 5: Many small bodies from aggressive cutting
**Problem:** Player cuts stone into 50 tiny pieces → 50 bodies × collision checks = potential slowdown.
**Mitigation:** (a) Bodies with <4 pixels auto-convert to powder. (b) Sleeping bodies are skipped. (c) Broad-phase AABB check before pixel collision. (d) At 320x180, even 100 active bodies with 50 pixels each = 5000 collision checks/frame = trivial on modern CPU.

### Risk 6: Shader push constant size limit (128 bytes)
**Problem:** We might want to pass body info to the shader.
**Mitigation:** We don't need to. Body info is encoded in the grid cell itself (body_id bits). The shader only needs to check `body_id > 0` to skip. No additional push constants needed.

### Risk 7: Wood falling causes chain reactions
**Problem:** Wood falls → exposes more unsupported wood → more falls → flood fill every frame.
**Mitigation:** Run wood support check every 10 frames (not every frame). Mark dirty regions. Once wood starts falling (becomes `WOOD_FALLING`), the CA shader handles the rest — no more CPU intervention needed until it lands.

---

## 10. Detailed Data Flow Example

### Scenario: Player cuts a stone bridge in half

```
Frame N:
  - Player clicks "cut" tool at position (160, 90)
  - Cut removes a 3-pixel-wide column of stone

Frame N (damage detection):
  - physics_world.check_damage() finds body #7 has lost pixels
  - BFS from any remaining pixel in body #7
  - BFS cannot reach all pixels → SPLIT detected
  - Two components found: left_pixels (200 px) and right_pixels (150 px)

Frame N (split):
  - Body #7 gets left_pixels, recalculate CoM, mass=200
  - New body #23 gets right_pixels, recalculate CoM, mass=150
  - Grid pixels updated: right side cells get body_id=23
  - Both bodies inherit body #7's velocity (was 0,0 since static bridge)

Frame N+1:
  - Gravity applied: both bodies velocity.y += 0.5
  - Both bodies move down by 0.5 pixels (subpixel, rounds to 0 or 1)

Frame N+2:
  - velocity.y = 1.0, bodies clearly falling
  - Left side hits a surface → collision response, velocity zeroed
  - Right side still falling

Frame N+10:
  - Right side hits water → displaces water pixels (CA handles splash)
  - Body barely moving → sleep_counter increasing

Frame N+40:
  - Right side sleeping → optionally dissolve back to static stone pixels
```

---

## 11. Alternative Designs Considered

### Alternative A: Use Godot's built-in RigidBody2D
**Rejected.** Godot physics operates in a different coordinate space, doesn't understand our pixel grid, and would require constant conversion between physics shapes and grid data. The overhead of maintaining two parallel representations outweighs the benefit of built-in collision solving.

### Alternative B: Run CCL on GPU (compute shader)
**Rejected for now.** GPU CCL algorithms exist (parallel Union-Find, label equivalence) but are complex to implement in GLSL 450 and require multiple dispatch passes with barriers. At 320x180, CPU CCL is <1ms. Not worth the complexity. Could revisit if grid size increases to 1920x1080+.

### Alternative C: Make wood a rigid body too
**Rejected.** Wood burns, which would require constant body shape recalculation. The "falling when unsupported" behavior is much simpler to implement as a material state change. If rigid wood is desired later, the rigid body system will already exist and wood can be added.

### Alternative D: Chunk-based simulation (like Noita's 64x64 chunks)
**Deferred.** At 320x180, the entire grid fits in L1 cache. Chunking adds complexity without performance benefit. If the grid grows to 1280x720+, chunking should be revisited.

---

## 12. Performance Budget

| Operation | Est. Time | Frequency |
|-----------|-----------|-----------|
| GPU CA simulation (6 passes) | ~2ms | Every frame |
| GPU↔CPU download | ~0.3ms | Every frame |
| Rigid body physics step (10 active bodies) | ~0.5ms | Every frame |
| Body rasterization (10 bodies, ~200px each) | ~0.2ms | Every frame |
| CPU→GPU upload (post-rasterize) | ~0.3ms | Every frame |
| Wood support check | ~0.5ms | Every 10th frame |
| CCL on damage (single body, ~500px) | ~0.1ms | On damage only |
| Body split + polygon gen | ~0.2ms | On split only |
| Render | ~1ms | Every frame |
| **Total (typical frame)** | **~4.3ms** | **~230 FPS headroom** |

At 320x180, we have enormous performance margin. The bottleneck will remain the GPU simulation passes.

---

## 13. Future Extensions

Once the core system works, these become possible:

- **Explosive forces:** Apply radial impulse to nearby bodies
- **Joints/constraints:** Pin two bodies together (hinges, rope)
- **Buoyancy:** Bodies float in water (check overlap with water pixels)
- **Material-specific rigid bodies:** Ice (slippery), metal (heavy), etc.
- **Larger world:** With chunking, scale to 1280x720 or beyond
- **Player character as rigid body:** Platformer physics integrated with pixel world

---

## Sources

Research references used for this specification:

- [Noita: a Game Based on Falling Sand Simulation — 80.lv](https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation)
- [Exploring the Tech and Design of 'Noita' — GDC Vault](https://www.gdcvault.com/play/1025695/Exploring-the-Tech-and-Design)
- [Video: Understanding the remarkable tech and design of Noita — Game Developer](https://www.gamedeveloper.com/design/video-understanding-the-remarkable-tech-and-design-of-i-noita-i-)
- [Bridging Physics Worlds — Slow Rush Games](https://www.slowrush.dev/news/bridging-physics-worlds/)
- [FallingSandSurvival — Rigid Body Discussion](https://github.com/PieKing1215/FallingSandSurvival/issues/3)
- [Connected-component labeling — Wikipedia](https://en.wikipedia.org/wiki/Connected-component_labeling)
- [GPU CCL Algorithm — NVIDIA GTC 2019](https://developer.download.nvidia.com/video/gputechconf/gtc/2019/presentation/s9111-a-new-direct-connected-component-labeling-and-analysis-algorithm-for-gpus.pdf)
- [Exploring the tech and design of 'Noita' — Tildes discussion](https://tildes.net/~games/hsh/exploring_the_tech_and_design_of_noita)
