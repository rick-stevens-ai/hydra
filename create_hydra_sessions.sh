#!/bin/bash
# Create all registered hydra coordinator sessions non-interactively.
set -u
REG="$HOME/.hermes/hydra_registry"
CREATED="$HOME/.hermes/hydra_created"
touch "$CREATED"

purpose_for() {
  case "$1" in
    osti)    echo "OSTI corpus gap-closing + 3-store durability (SG-1-8TB primary, DGX, Polaris/Eagle), recovery_worker, CDP recovery, DOI discovery, catalog reconciliation.";;
    scout)   echo "SCOUT-CORPUS build: 95K unique PDFs, 14-domain taxonomy (DESIGN.md), Stage-2 LLM classification, stub recovery, replicate to Eagle/Flare, PullR fill.";;
    parse)   echo "Marker (Polaris) + Nougat (Aurora/Polaris) continuous parse pipeline feeding both OSTI and SCOUT corpora; restartable/chainable HPC jobs, reapers, corrupt-PDF recovery.";;
    bench)   echo "pi-benchmark / fleet-eval: pi-problems-30 sweeps, CELS model serving, cross-model matrix, GPQA reruns with provenance discipline, coordination with Ollie.";;
    aien)    echo "AI-ENVIRONMENT: CELS VPS + model-server fleet (chicago-N endpoints, vLLM tool-parsers, --host 0.0.0.0 bind symmetry, LiteLLM on CherryRd), endpoint health. Source of truth: ~/Dropbox/AIEN.";;
    memory)  echo "Agent memory systems: layered memory stack, STRATUS shadow dual-run, UMP shared store. Weekly review, distiller, migration hygiene. Cross-agent coordination.";;
    sibline) echo "Kukla<->Ollie comms transport: NATS+JetStream broker, subscriber daemon, kukla-mail, Telegram/Slack bridges, webhook subscriptions.";;
    hpc)     echo "HPC builds: QE-PVC on chiatta00, Intel oneAPI toolchain, MP-LINPACK, distributed-DFT. Testbed sysadmin authority.";;
    self-ops) echo "Kukla self-ops: sitrep email, gateway lifecycle, memory/vault maintenance, hydra multi-session coordination setup.";;
    *)       echo "$1 workstream.";;
  esac
}

while IFS= read -r name; do
  [ -z "$name" ] && continue
  if grep -Fxq "$name" "$CREATED"; then
    echo "[skip] $name already created"
    continue
  fi
  seed="Coordinator session for the '$name' workstream. Purpose: $(purpose_for "$name") This is a persistent high-level coordinator; it will delegate work to subagents. Reply with just: ready."
  echo "=== creating: $name ==="
  out="$(hermes chat -Q -q "$seed" --max-turns 1 2>&1)"
  sid="$(printf '%s\n' "$out" | grep -oE 'session_id: [0-9a-z_]+' | head -1 | awk '{print $2}')"
  if [ -z "$sid" ]; then
    echo "[FAIL] $name — no session_id captured. Output tail:"
    printf '%s\n' "$out" | tail -5
    continue
  fi
  hermes sessions rename "$sid" "$name" >/dev/null 2>&1
  echo "$name" >> "$CREATED"
  echo "[ok] $name -> $sid (titled + marked)"
done < "$REG"

echo
echo "=== hydra_created ==="
cat "$CREATED"
