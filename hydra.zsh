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

HYDRA_REGISTRY="$HOME/.hermes/hydra_registry"
HYDRA_CREATED="$HOME/.hermes/hydra_created"

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
  local name="$1"
  if [ -z "$name" ]; then
    echo "usage: hydra <name>   (known: $(tr '\n' ' ' < "$HYDRA_REGISTRY" 2>/dev/null))"
    return 1
  fi
  touch "$HYDRA_REGISTRY" "$HYDRA_CREATED"

  # 1) tmux session already live -> attach
  if tmux has-session -t "$name" 2>/dev/null; then
    echo "[hydra] attaching to running tmux session '$name'"
    tmux attach -t "$name"
    return 0
  fi

  # 2) already created+titled -> resume the titled Hermes session
  if grep -Fxq "$name" "$HYDRA_CREATED"; then
    echo "[hydra] resuming titled Hermes session '$name'"
    tmux new-session -d -s "$name" "hermes -c '$name'"
    echo "[hydra] attaching (detach: Ctrl-b d)"
    tmux attach -t "$name"
    return 0
  fi

  # 3) new (or registered-only) -> create fresh session; auto-title+mark on exit
  echo "[hydra] spawning NEW Hermes coordinator '$name' (auto-titles on exit)"
  grep -Fxq "$name" "$HYDRA_REGISTRY" || echo "$name" >> "$HYDRA_REGISTRY"
  # After `hermes` exits, capture newest ID, rename to $name, mark created.
  tmux new-session -d -s "$name" \
    "hermes; source '$HOME/.hermes/hydra.zsh'; hydra-finalize '$name'; echo; echo '[hydra] $name is now resume-ready. Ctrl-b d to detach this shell, or exit.'; exec zsh"
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
