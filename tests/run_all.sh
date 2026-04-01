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

# GPU-skenaariot
for f in "$PROJECT/tests/scenarios"/*.json; do
  echo "--- $f"
  output=$("$GODOT" --path "$PROJECT" -- --scenario="res://tests/scenarios/$(basename $f)" 2>&1)
  echo "$output"
  if echo "$output" | grep -q "ScenarioRunner: FAIL\|failed=[^0]"; then
    FAIL=$((FAIL+1))
  else
    PASS=$((PASS+1))
  fi
done

echo ""
echo "========================="
echo "TOTAL: passed=$PASS failed=$FAIL"
echo "========================="
[ $FAIL -eq 0 ] && exit 0 || exit 1
