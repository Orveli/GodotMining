#!/bin/bash
# Ajaa kaikki GodotMining-testit
GODOT="/c/Users/mauri/Desktop/Godot/Godot_v4.6.1-stable_win64_console.exe"
PROJECT="/c/Users/mauri/Desktop/Git/GodotMining"
PASS=0
FAIL=0

# CPU-yksikkötestit
for f in "$PROJECT/tests/unit"/test_*.gd; do
  echo "--- $f"
  output=$("$GODOT" --headless --path "$PROJECT" --script "res://tests/unit/$(basename $f)" 2>&1)
  echo "$output"
  if echo "$output" | grep -q "TEST: FAIL\|FAILED\|Error"; then
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+1))
  fi
done

# GPU-skenaariot (CA-fysiikka vaatii Vulkan-renderin -> ajetaan ikkunallisena).
# mvp_core_loop ohitetaan tassa; se ajetaan erikseen headlessina alla.
# HUOM: ikkunallista Vulkania vaativat skenaariot (hihnat + koneet) ajetaan tässä
# ilman --headless-lippua. Näihin kuuluvat conveyor_*.json ja belt_ore.json —
# ne EIVÄT toimi headless-ympäristössä (tarvitsevat renderöivän kontekstin).
for f in "$PROJECT/tests/scenarios"/*.json; do
  [ "$(basename "$f")" = "mvp_core_loop.json" ] && continue
  echo "--- $f"
  output=$("$GODOT" --path "$PROJECT" -- --scenario="res://tests/scenarios/$(basename $f)" 2>&1)
  echo "$output"
  if echo "$output" | grep -q "ScenarioRunner: FAIL\|failed=[^0]"; then
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+1))
  fi
done

# E2E-bottiskenaario (GDD Vaihe 1) — CPU-bottisimulaatio, EI vaadi GPU:ta.
# Ajetaan headlessina: gpu_ready=false -> pixel_world ajaa bottisimulaation + CPU-CA:n
# (cpu_ca=true) kiintealla aika-askeleella (deterministinen). Miner muuntaa STONE->GRAVEL /
# loysentaa granulaarit, CA valuttaa irtomateriaalin kuopan pohjalle, hauler imuroi ja purkaa
# baseen. Kynnykset sidottu designaation kokoon (osuus-assert) -> todistaa etenevan louhinnan
# ja BLOCKED-reaktivoinnin (ei frontier-jumia).
echo "--- $PROJECT/tests/scenarios/mvp_core_loop.json (headless)"
output=$("$GODOT" --headless --path "$PROJECT" -- --scenario="res://tests/scenarios/mvp_core_loop.json" 2>&1)
echo "$output"
if echo "$output" | grep -q "ScenarioRunner: FAIL\|failed=[^0]"; then
  FAIL=$((FAIL+1))
else
  PASS=$((PASS+1))
fi

echo ""
echo "========================="
echo "TOTAL: passed=$PASS failed=$FAIL"
echo "========================="
[ $FAIL -eq 0 ] && exit 0 || exit 1
