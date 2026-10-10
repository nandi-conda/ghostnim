/// Self-update for the AppImage build.
///
/// Release builds made by CI (built with --dart-define=AUTO_UPDATE=true)
/// check GitHub for a newer AppImage at most once a day, in a detached
/// background process. The `release`-tagged GitHub release carries a .zsync
/// file next to the AppImage; its SHA-1 line identifies the release build. If
/// it differs from the running AppImage, the new one is downloaded, verified
/// against that SHA-1 and renamed over the old file, so the next launch runs
/// it. The running instance is unaffected, since the AppImage runtime keeps
/// the old file open.
///
/// Needs curl and sha1sum on the host; without them it does nothing. Set
/// GHOSTNIM_NO_UPDATE=1 to turn the launch check off.
///
/// "Check for Updates" in the right-click menu runs the same script right
/// away, skipping the once-a-day limit, and reports the outcome with
/// notify-send.
library;

import 'dart:io';

const _autoUpdate = bool.fromEnvironment('AUTO_UPDATE');
const _updateRepo = String.fromEnvironment('UPDATE_REPO', defaultValue: 'codegod100/ghostnim');

// Runs with $0 = the AppImage path and $1 = "manual" for a check the user
// asked for. Everything it needs is on the host, so it keeps working after
// ghostnim exits and the AppImage is unmounted.
const _updateScript = r'''
set -eu
app=$0
manual=${1:-}
say() {
  [ -n "$manual" ] && command -v notify-send >/dev/null &&
    notify-send -a ghostnim ghostnim "$1" || true
}
command -v curl >/dev/null && command -v sha1sum >/dev/null ||
  { say "Can't check for updates: curl and sha1sum are needed."; exit 0; }
[ -w "$(dirname "$app")" ] && [ -w "$app" ] ||
  { say "Can't update: $app isn't writable."; exit 0; }
cache=${XDG_CACHE_HOME:-$HOME/.cache}/ghostnim
mkdir -p "$cache"
stamp=$cache/last-update-check
if [ -z "$manual" ]; then
  [ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ] && exit 0
fi
touch "$stamp"
base=https://github.com/$UPDATE_REPO/releases/download/release/ghostnim-$(uname -m).AppImage
want=$(curl -fsSL --max-time 30 "$base.zsync" | sed -n 's/^SHA-1: *\([0-9a-f]*\).*/\1/p')
[ -n "$want" ] || { say "Couldn't check for updates."; exit 0; }
[ "$(sha1sum "$app" | cut -d' ' -f1)" = "$want" ] && { say "ghostnim is up to date."; exit 0; }
say "Downloading an update..."
tmp=$(mktemp "$app.update.XXXXXX")
trap 'rm -f "$tmp"' EXIT
curl -fsSL --max-time 600 -o "$tmp" "$base" || { say "Downloading the update failed."; exit 0; }
[ "$(sha1sum "$tmp" | cut -d' ' -f1)" = "$want" ] ||
  { say "The downloaded update didn't verify; not installed."; exit 0; }
chmod 755 "$tmp"
mv -f "$tmp" "$app"
trap - EXIT
say "ghostnim updated. Restart it to run the new version."
''';

/// Whether this is a self-updating build running from an AppImage.
bool canUpdate() => _autoUpdate && (Platform.environment['APPIMAGE'] ?? '').isNotEmpty;

/// Kick off the background update check when running from a CI AppImage.
/// A manual check ignores the daily limit and GHOSTNIM_NO_UPDATE.
void startUpdateCheck({bool manual = false}) {
  if (!canUpdate()) return;
  if (!manual && (Platform.environment['GHOSTNIM_NO_UPDATE'] ?? '').isNotEmpty) return;
  Process.start(
    '/bin/sh',
    ['-c', _updateScript, Platform.environment['APPIMAGE']!, if (manual) 'manual' else ''],
    environment: {'UPDATE_REPO': _updateRepo},
    mode: ProcessStartMode.detached,
  ).ignore();
}
