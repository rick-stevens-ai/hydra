# hydra

Labeled multi-session coordination for [Hermes Agent](https://hermes-agent.nousresearch.com).

`hydra` turns a Hermes install into an OpenClaw-style **main + workers** fan-out that
you can run *many times in parallel*. Each labeled session is a long-lived **coordinator**
that keeps its own conversation/context and delegates real work to a swarm of subagents.
Many heads, one body.

```
                        ┌─ hydra osti ──┐   coordinator → subagents (depth 2, ×6)
   you  ──── launch ────┼─ hydra scout ─┤   coordinator → subagents
                        ├─ hydra parse ─┤   coordinator → subagents
                        └─ hydra bench ─┘   ...
```

The point: your **main** Hermes loop stays free (e.g. for continuous peer-agent
coordination), while each `hydra <name>` is an independent coordinator you can attach to,
detach from, and resume by name — its context persists across detaches and restarts.

---

## Why this exists

Hermes sessions are single-threaded conversations. Running several concurrent
workstreams — each needing its own persistent context and its own subagent budget —
means juggling several named sessions. Doing that by hand is tedious:

- `hermes -c <name>` **resumes only** (it will not create); you have to create the
  session first, then title it, then remember the exact name.
- Interactive `hermes` needs a real TTY (prompt_toolkit), so you can't just background it.
- There's no built-in registry of "these are my standing coordinators."

`hydra` closes those gaps with one command per label plus a tiny two-file state model.

---

## Install

Requires: `hermes` on `PATH`, `tmux`, `bash`/`zsh`.

```sh
git clone <this-repo> ~/code/hydra
echo '[ -f ~/code/hydra/hydra.zsh ] && source ~/code/hydra/hydra.zsh' >> ~/.zshrc
source ~/.zshrc
```

The helper reads/writes two small state files under `~/.hermes/`:

| file             | meaning                                                             |
|------------------|--------------------------------------------------------------------|
| `hydra_registry` | the coordinator names you *intend* to run (you curate this list)    |
| `hydra_created`  | names whose underlying Hermes session exists + is titled (auto-managed) |

Seed the registry with your standing workstreams (see `hydra_registry.example`):

```sh
cp ~/code/hydra/hydra_registry.example ~/.hermes/hydra_registry
```

---

## Usage

### One command per coordinator

```sh
hydra osti      # attach if live; resume if created; else spawn NEW + auto-title on exit
```

`hydra <name>` resolves in three cases:

1. **tmux session `<name>` already live**  → attach to it.
2. **`<name>` is in `hydra_created`**       → resume the titled Hermes session (`hermes -c <name>`) inside a fresh tmux window.
3. **new / registered-only**               → spawn a fresh Hermes session. As soon as
   that `hermes` process **exits**, the newest session is auto-titled `<name>` and
   marked created — so next time, case 2 applies.

Detach any coordinator with `Ctrl-b d` (Hermes keeps running; resume later).

### Bulk-create all registered coordinators (non-interactive)

Instead of walking N interactive TTYs, `create_hydra_sessions.sh` seeds every name in
`hydra_registry` in one shot. It uses Hermes' non-interactive query mode
(`hermes chat -Q -q "..." --max-turns 1`), which **creates a persisted session and
prints `session_id: <ID>` on stdout** — no TTY needed. Each session is then renamed to
its label and marked created. Idempotent: names already in `hydra_created` are skipped.

```sh
bash ~/code/hydra/create_hydra_sessions.sh
```

Edit `purpose_for()` in that script to set each coordinator's seed prompt.

### Helpers

| command                | effect                                                              |
|------------------------|--------------------------------------------------------------------|
| `hydra-ls`             | show registry + created + live tmux sessions                        |
| `hydra-finalize <name>`| title the newest session to `<name>` + mark created (manual trigger)|
| `hydra-mark <name>`    | mark a name created without renaming                                |
| `hydra-kill <name>`    | tear down the tmux window (Hermes session survives, still resumable)|

---

## How auto-titling works (and its one caveat)

When you `hydra <name>` a *new* label, the spawn command is:

```sh
tmux new-session -d -s <name> \
  "hermes; source ~/code/hydra/hydra.zsh; hydra-finalize <name>; ...; exec zsh"
```

So the rename+mark fires **when the `hermes` process exits** (you `/exit`, or it ends).

**Caveat:** if you only *detach* with `Ctrl-b d` (leaving `hermes` running), auto-title
has **not** fired yet — the name isn't in resume-mode until you later attach and exit.
To title a still-running session without exiting it, run `hydra-finalize <name>` from
any terminal after you've sent at least one message. (The bulk creator sidesteps this
entirely by using non-interactive mode.)

---

## Recommended Hermes config for coordinators

Coordinators are only useful if they can actually fan out. Set in `~/.hermes/config.yaml`:

```yaml
agent:
  pass_session_id: true          # subagents inherit the coordinator's session id
delegation:
  max_concurrent_children: 6     # subagents per coordinator, in parallel
  max_spawn_depth: 2             # coordinator → sub-coordinator → worker
```

With depth 2 and 6 children, worst-case fan-out is 6×6 = 36 leaf workers under one
coordinator. Tune to your box.

---

## Design notes

- **`-c` is resume-only.** Verified against Hermes' CLI. Session creation is a separate
  step (interactive `hermes`, or `hermes chat -q`). `hydra` papers over this.
- **Two-state model.** `hydra_registry` (intent) vs `hydra_created` (reality) are kept
  distinct so you can plan coordinators before they exist and see the gap with `hydra-ls`.
- **macOS bash is 3.2** — no associative arrays. The bulk creator uses a `case` statement
  (`purpose_for()`) rather than `declare -A`.
- **Non-interactive creation.** `hermes chat -Q -q "<seed>" --max-turns 1` persists a
  session and emits a parseable `session_id: <ID>` line — the key that makes bulk
  creation possible without driving N terminals.

## Files

| file                        | what                                                       |
|-----------------------------|------------------------------------------------------------|
| `hydra.zsh`                 | the `hydra` function + helpers; source this from your rc   |
| `create_hydra_sessions.sh`  | bash-3.2-safe idempotent bulk creator                      |
| `hydra_registry.example`    | example standing-coordinator list                          |

## License

MIT
