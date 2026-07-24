# hydra: launch/attach a labeled Hermes coordinator session in tmux.
# Each named session is a coordinator that fans out its own subagent swarm —
# many heads, one body.
#
#   hydra <name>
#
# State model — two files under ~/.hermes/:
#   hydra_registry  : the intended coordinator names (you curate this list).
#   hydra_created   : names whose underlying Hermes session has been created+titled
#                     (managed automatically).
#
# Behavior of `hydra <name>`:
#   - tmux session <name> already live      -> attach.
#   - name is in hydra_created              -> resume titled Hermes session (`hermes -c`).
#   - otherwise (new or registered-only)    -> create a fresh Hermes session; AS SOON AS
#                                              that session exits/detaches, auto-title the
#                                              newest session to <name> and mark it created.
#                                              No manual rename or mark needed.
#
# NOTE ON AUTO-TITLE: the title/mark fires when the `hermes` process EXITS (you `/exit`
# or the process ends). If you only detach with Ctrl-b d (leaving hermes running), the
# auto-title has NOT fired yet — it will fire when you later attach and exit. Until then
# the name is not yet in resume-mode. To title without exiting, run `hydra-finalize <name>`
# from any terminal after you've sent at least one message.
#
# Helpers:
#   hydra-ls              list registry + created + live tmux sessions
#   hydra-finalize <name> title the newest session to <name> + mark created (manual trigger)
#   hydra-mark <name>     just mark a name as created (no rename)
#   hydra-kill <name>     tear down the tmux window (Hermes session survives, resumable)
#   hydra-help            show the full command surface (also: hydra --help)

HYDRA_REGISTRY="$HOME/.hermes/hydra_registry"
HYDRA_CREATED="$HOME/.hermes/hydra_created"

# print the full hydra command surface
hydra-help() {
  cat <<'EOF'
hydra — launch/attach labeled, resumable Hermes coordinator sessions in tmux.

USAGE
  hydra <name>                 attach/resume a coordinator TUI (in tmux) for <name>
                               (spawns + auto-titles a new Hermes session if needed)
  hydra <name> "<msg>"         one-shot: send <msg> to <name>, print reply (no TTY)
  hydra --help | -h | --h      show this help

COMMANDS
  hydra <name>                 attach if live / resume if created / else spawn-new
  hydra <name> "<msg>"         send a one-shot message and print the reply
  hydra-send <name> "<msg>"    fire a message to a coordinator (one-shot)
  hydra-ls                     list registry + created + live tmux sessions
  hydra-tail                   live-tail Hermes' conversation log
  hydra-kill <name>            tear down the tmux window (Hermes session survives)
  hydra-pin <name> | --all     courtesy keep-warm ping (Hermes doesn't daily-reset)
  hydra-seed                   bulk-create every registered coordinator w/ a purpose prompt
  hydra-finalize <name>        title the newest session to <name> + mark created
  hydra-mark <name>            mark a name created without renaming
  hydra-help                   show this help

ENVIRONMENT
  HYDRA_REGISTRY   intended-coordinators file (default: ~/.hermes/hydra_registry)
  HYDRA_CREATED    created (resume-mode) names  (default: ~/.hermes/hydra_created)
  HYDRA_MAX_TURNS  turn cap for one-shot sends   (default: 30)
EOF
}

# capture newest session ID (first data row of `hermes sessions list`, last column)
_hydra_newest_id() {
  hermes sessions list 2>/dev/null | awk 'NR==3{print $NF}'
}

hydra-finalize() {
  local name="$1"
  if [ -z "$name" ]; then echo "usage: hydra-finalize <name>"; return 1; fi
  local id
  id="$(_hydra_newest_id)"
  if [ -z "$id" ]; then
    echo "[hydra] could not find a session to title (send a message first)"; return 1
  fi
  hermes sessions rename "$id" "$name" >/dev/null 2>&1 \
    && echo "[hydra] titled newest session $id -> '$name'"
  touch "$HYDRA_CREATED"
  grep -Fxq "$name" "$HYDRA_CREATED" || echo "$name" >> "$HYDRA_CREATED"
  echo "[hydra] '$name' marked created -> future hydra $name will RESUME it"
}

hydra() {
  local name="$1"; shift 2>/dev/null
  case "$name" in
    -h|--h|--help|help)
      hydra-help
      return 0
      ;;
  esac
  if [ -z "$name" ]; then
    echo "usage: hydra <name> [\"message\"]   (known: $(tr '\n' ' ' < "$HYDRA_REGISTRY" 2>/dev/null))"
    echo "       hydra --help   for the full command list"
    return 1
  fi
  touch "$HYDRA_REGISTRY" "$HYDRA_CREATED"

  # one-shot mode: `hydra <name> "message"` -> send + print reply, no interactive TTY
  if [ "$#" -gt 0 ] && [ -n "$1" ]; then
    hydra-send "$name" "$*"
    return $?
  fi

  # 1) tmux session already live -> attach
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "[hydra] attaching to running tmux session '$name'"
    tmux attach -t "$name"
    return 0
  fi

  # 2) already created+titled -> resume the titled Hermes session
  if grep -Fxq "$name" "$HYDRA_CREATED"; then
    echo "[hydra] resuming titled Hermes session '$name'"
    tmux new-session -d -s "$name" "hermes --yolo -c '$name'"
    echo "[hydra] attaching (detach: Ctrl-b d)"
    tmux attach -t "$name"
    return 0
  fi

  # 3) new (or registered-only) -> create fresh session; auto-title+mark on exit
  echo "[hydra] spawning NEW Hermes coordinator '$name' (auto-titles on exit)"
  grep -Fxq "$name" "$HYDRA_REGISTRY" || echo "$name" >> "$HYDRA_REGISTRY"
  # After `hermes` exits, capture newest ID, rename to $name, mark created.
  tmux new-session -d -s "$name" \
    "hermes --yolo; source '$HOME/.hermes/hydra.zsh'; hydra-finalize '$name'; echo; echo '[hydra] $name is now resume-ready. Ctrl-b d to detach this shell, or exit.'; exec zsh"
  echo "[hydra] attaching (detach: Ctrl-b d)"
  tmux attach -t "$name"
}

hydra-mark() {
  local name="$1"
  if [ -z "$name" ]; then echo "usage: hydra-mark <name>"; return 1; fi
  touch "$HYDRA_CREATED"
  if grep -Fxq "$name" "$HYDRA_CREATED"; then
    echo "[hydra] '$name' already marked created"
  else
    echo "$name" >> "$HYDRA_CREATED"
    echo "[hydra] marked '$name' as created -> future hydra $name will RESUME it"
  fi
}

hydra-ls() {
  echo "== registry (intended names) =="
  [ -s "$HYDRA_REGISTRY" ] && cat "$HYDRA_REGISTRY" || echo "(none)"
  echo
  echo "== created (resume-mode) =="
  [ -s "$HYDRA_CREATED" ] && cat "$HYDRA_CREATED" || echo "(none)"
  echo
  echo "== live tmux sessions =="
  tmux ls 2>/dev/null || echo "(no tmux server running)"
}

hydra-kill() {
  local name="$1"
  if [ -z "$name" ]; then echo "usage: hydra-kill <name>"; return 1; fi
  tmux kill-session -t "$name" 2>/dev/null && echo "[hydra] killed tmux session '$name'" \
    || echo "[hydra] no live tmux session '$name'"
}

# --- symmetric surface with argus (the OpenClaw analog) ---

hydra-send() {
  # One-shot: send a message to coordinator <name>, print reply, no interactive TTY.
  # Resume-by-name via `hermes chat -c` (the session must already be created; use
  # `hydra <name>` once, or `create_hydra_sessions.sh` / hydra-seed, to create it).
  local name="$1"; shift
  if [ -z "$name" ] || [ -z "$*" ]; then echo "usage: hydra-send <name> \"message\""; return 1; fi
  if ! grep -Fxq "$name" "$HYDRA_CREATED" 2>/dev/null; then
    echo "[hydra] '$name' is not created yet — run 'hydra $name' once (or hydra-seed) to create it, then retry."
    return 1
  fi
  hermes chat -Q --yolo -c "$name" -q "$*" --max-turns "${HYDRA_MAX_TURNS:-30}"
}

hydra-tail() {
  # Live-tail Hermes' main conversation log (no per-session tail in the CLI).
  local logf="$HOME/.hermes/logs/agent.log"
  if [ ! -f "$logf" ]; then echo "[hydra] no log at $logf"; return 1; fi
  echo "[hydra] tailing $logf (Ctrl-c to stop)"
  tail -f "$logf"
}

hydra-pin() {
  # Keep-warm a coordinator. NOTE: Hermes sessions do NOT daily-reset like OpenClaw,
  # so pinning is mostly unnecessary here — this exists for argus parity and sends a
  # tiny no-op turn to keep the session recent. Use --all for every created name.
  local name="$1"
  if [ -z "$name" ]; then echo "usage: hydra-pin <name>   (or: hydra-pin --all)"; return 1; fi
  if [ "$name" = "--all" ]; then
    [ -s "$HYDRA_CREATED" ] || { echo "[hydra] no created coordinators"; return 0; }
    while IFS= read -r n; do [ -z "$n" ] && continue; hydra-pin "$n"; done < "$HYDRA_CREATED"
    return 0
  fi
  echo "[hydra] keep-warm '$name' (Hermes sessions don't daily-reset; pin is a courtesy ping)"
  hermes chat -Q --yolo -c "$name" -q "keep-warm ping; reply with just: ok" --max-turns 1 >/dev/null 2>&1 \
    && echo "[hydra] pinged '$name'" || echo "[hydra] could not ping '$name' (created yet?)"
}

hydra-seed() {
  # Bulk-create every registered coordinator non-interactively (alias for the script).
  bash "$HOME/.hermes/create_hydra_sessions.sh" 2>/dev/null \
    || bash "$(dirname "${(%):-%x}" 2>/dev/null || echo "$HOME/code/hydra")/create_hydra_sessions.sh"
}
