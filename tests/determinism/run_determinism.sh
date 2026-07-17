#!/bin/bash
# P2 determinismi- + perf-vertailu — AJETAAN IKKUNALLISENA (GPU-CA vaatii Vulkanin).
# Integraattori ajaa tämän yhtenä eränä. Vertaa jokaisen skenaarion "HASH"-lokiriviä
# activity=1 vs activity=0.
#
#   bash tests/determinism/run_determinism.sh
#
# ODOTUS:
#  - DETERMINISTISET (jauhe/kiinteä/asettuva): hash TÄSMÄLLEEN sama ON vs OFF.
#  - STOKASTISET (neste/höyry): hash EROAA myös ajokertojen välillä (GPU atomic-race,
#    pre-existing — kaksi activity=1-ajoakin eroavat). Vertaa counts={} -jakaumaa:
#    activity=1:n laskurit osuvat samalle kaistalle kuin activity=0:n.
set -u
GODOT="/c/Users/mauri/Desktop/Godot/Godot_v4.6.1-stable_win64_console.exe"
PROJ="/c/Users/mauri/Desktop/Git/GodotMining/.claude/worktrees/perf-p2"

DETERMINISTIC="det_sand_falls det_stone_stacks det_explosion_fragments"
STOCHASTIC="det_water_flows det_steam_rises"

run() { # scenario, activity
  timeout 180 "$GODOT" --path "$PROJ" -- \
    --scenario="res://tests/determinism/$1.json" --activity=$2 2>&1 \
    | grep "ScenarioRunner: HASH" | head -1
}

echo "########## DETERMINISTISET (hash pitää täsmätä bit-tarkasti) ##########"
for s in $DETERMINISTIC; do
  on=$(run "$s" 1); off=$(run "$s" 0)
  ha=$(echo "$on"  | sed -n 's/.*hash=\(-\?[0-9]*\).*/\1/p')
  hb=$(echo "$off" | sed -n 's/.*hash=\(-\?[0-9]*\).*/\1/p')
  echo "--- $s"; echo "  ON : $on"; echo "  OFF: $off"
  [ -n "$ha" ] && [ "$ha" = "$hb" ] && echo "  => MATCH" || echo "  => *** EROAA — TUTKI ***"
done

echo ""
echo "########## STOKASTISET (vertaa counts-jakaumaa, ei hashia) ##########"
for s in $STOCHASTIC; do
  echo "--- $s"
  echo "  ON  x3:"; for i in 1 2 3; do run "$s" 1 | sed 's/.*activity/    activity/'; done
  echo "  OFF x3:"; for i in 1 2 3; do run "$s" 0 | sed 's/.*activity/    activity/'; done
done

echo ""
echo "########## PERF (asettunut maailma, gpu_bench synkroninen) ##########"
echo "-- ON --";  timeout 120 "$GODOT" --path "$PROJ" -- --scenario="res://tests/determinism/perf_bench.json" --activity=1 2>&1 | grep "gpu_bench"
echo "-- OFF --"; timeout 120 "$GODOT" --path "$PROJ" -- --scenario="res://tests/determinism/perf_bench.json" --activity=0 2>&1 | grep "gpu_bench"
