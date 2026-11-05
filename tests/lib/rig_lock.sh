# Locks for what concurrent runs of the live packs share. Sourced by the
# runLocal.sh scripts, never executed.
#
# A key names the shared thing as <kind>:<absolute path>, so every run that
# touches it contends for the same lock. Written for bash 3.2, which is what
# macOS ships.

RIG_LOCK_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Holds the lock on <key> until this script exits, waiting while another run
# holds it.
rig_lock() {
  local dir line
  dir="$(mktemp -d "${TMPDIR:-/tmp}/rig_lock.XXXXXX")"
  mkfifo "$dir/fifo"
  python3 "$RIG_LOCK_LIB/hold_lock.py" "$1" "$$" > "$dir/fifo" &
  RIG_LOCK_HOLDER=$!
  disown "$RIG_LOCK_HOLDER"
  IFS= read -r line < "$dir/fifo" || true
  rm -rf "$dir"
  if [[ "$line" != locked ]]; then
    echo "*** Could not lock $1" >&2
    exit 1
  fi
}

# Runs a command holding the lock on <key>, then releases it.
with_rig_lock() {
  local key="$1" holder rc=0
  shift
  rig_lock "$key"
  holder="$RIG_LOCK_HOLDER"
  "$@" || rc=$?
  kill "$holder" 2> /dev/null || true
  return "$rc"
}

# Holds the lock on the pack in the current directory until this script exits.
# Two runs of one pack in one checkout share its test/hive, its keyfiles and
# its compose project, so the second waits for the first rather than wrecking
# it.
lock_pack() {
  rig_lock "pack:$PWD"
}

# Runs `dart pub get` holding the workspace's pub lock. Every pack resolves
# into the one pubspec.lock and .dart_tool at the workspace root, so two packs
# resolving at once race on the same files.
pub_get_locked() {
  with_rig_lock "pub:$(cd "$RIG_LOCK_LIB/../.." && pwd)" dart pub get
}
