# Shared settings for the personal scripts. Sourced, not executed.
#
# Every value can be overridden from the environment or from personal/config.local.env (gitignored).

PERSONAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PERSONAL_DIR/.." && pwd)"
# shellcheck disable=SC1091
[ -f "$PERSONAL_DIR/config.local.env" ] && . "$PERSONAL_DIR/config.local.env"

NOOP_REPO="${NOOP_REPO:-moamalr/noop}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-66R42699RQ}"
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.moamalrassan}"
APP_BUNDLE_ID="$BUNDLE_ID_PREFIX.noop"
WIDGET_BUNDLE_ID="$BUNDLE_ID_PREFIX.noop.widgets"
APP_GROUP_ID="group.$BUNDLE_ID_PREFIX.noop.staging"

# Where the phone's database snapshot and the MCP binary live on this Mac.
AGENT_HOME="${NOOP_AGENT_HOME:-$HOME/Library/Application Support/NOOP-Agent}"
SNAPSHOT_DB="$AGENT_HOME/whoop.sqlite"
LOCAL_ACCESS_BIN="$AGENT_HOME/bin/noop-local-access"

# Path of the store inside the iOS app's data container (Strand/Collect/StorePaths.swift).
DEVICE_DB_PATH="Library/Application Support/OpenWhoop/whoop.sqlite"

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

# Prints "<coredevice-identifier> <udid>" for the target iPhone: $NOOP_DEVICE (identifier, UDID or
# name) when set, otherwise the paired iPhone that is reachable now, preferring a cable.
resolve_device() {
  local json
  json="$(mktemp -t noop-devices)"
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || { rm -f "$json"; die "devicectl could not list devices"; }
  local rc=0
  python3 -I - "$json" "${NOOP_DEVICE:-}" <<'PY' || rc=$?
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2]
def ident(d):
    return {d["identifier"], d["hardwareProperties"].get("udid"), d["deviceProperties"].get("name")}
if want:
    match = [d for d in devices if want in ident(d)]
else:
    match = [d for d in devices
             if d["hardwareProperties"].get("deviceType") == "iPhone"
             and d["connectionProperties"].get("pairingState") == "paired"
             and d["connectionProperties"].get("tunnelState") in ("connected", "disconnected")]
    match.sort(key=lambda d: d["connectionProperties"].get("transportType") != "wired")
if not match:
    sys.exit("no reachable paired iPhone (set NOOP_DEVICE to pick one)")
d = match[0]
print(d["identifier"], d["hardwareProperties"]["udid"])
PY
  rm -f "$json"
  return $rc
}
