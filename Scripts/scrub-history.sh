#!/usr/bin/env zsh
# scrub-history.sh — find and remove Anthropic API keys from shell history.
#
# A companion utility to TouchSeal. Sealing a key in the Keychain does nothing
# about the copies your shell already recorded, and a key pasted into a command
# line lands in ~/.zsh_history in plaintext. This finds those and removes them.
#
#   Scripts/scrub-history.sh              # dry run: report matches (keys masked)
#   Scripts/scrub-history.sh --clean      # delete matching history entries
#   Scripts/scrub-history.sh --clean --redact
#                                         # keep entries, replace key with a placeholder
#   Scripts/scrub-history.sh --file PATH  # scan an extra file (repeatable)
#
# Scans $HISTFILE, ~/.zsh_sessions/*.history, and ~/.bash_history by default.
# Backs up every file it modifies to <file>.bak.<timestamp> (mode 0600).
#
# Exit codes:  0  nothing found, or a clean completed
#              1  dry run found matches (nothing changed)
#              2  bad arguments
#
# This script never prints an unmasked key, and never sends anything anywhere.

set -euo pipefail
setopt null_glob

mode=scan
redact=0
extra_files=()

while (( $# )); do
  case $1 in
    --clean)  mode=clean ;;
    --redact) redact=1 ;;
    --file)   shift; [[ $# -gt 0 ]] || { print -u2 "--file needs a path"; exit 2 }
              extra_files+=("$1") ;;
    -h|--help)
      sed -n '2,20s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
  shift
done

if [[ $mode == clean ]]; then
  (( redact )) && action=2 || action=1
else
  action=0
fi

# ---- files to scan -------------------------------------------------------
histfile=${HISTFILE:-$HOME/.zsh_history}
files=("$histfile" $HOME/.zsh_sessions/*.history "$HOME/.bash_history" $extra_files)

# de-dup, keep only readable regular files
typeset -U files
targets=()
for f in $files; do [[ -f $f && -r $f ]] && targets+=("$f"); done

if (( ${#targets} == 0 )); then
  print -u2 "No readable history files found."; exit 0
fi

# ---- the entry-aware scrubber --------------------------------------------
# Reads a history file on stdin, writes the cleaned file to stdout and a
# human-readable report to stderr. ACTION: 0=scan 1=delete 2=redact
#
# zsh history entries can span lines (a trailing odd number of backslashes
# continues the entry), so matches are evaluated per entry, not per line.
scrub_awk='
function trailing_bs(s,   n, L) {
  L = length(s); n = 0
  while (n < L && substr(s, L - n, 1) == "\\") n++
  return n
}
function mask(s) {
  gsub(/sk-ant-[A-Za-z0-9_-]+/, "sk-ant-<REDACTED>", s)
  gsub(/ANTHROPIC_(API_KEY|AUTH_TOKEN)=[^[:space:]]+/, "ANTHROPIC_KEY=<REDACTED>", s)
  return s
}
function flush(   masked) {
  if (! seen) return
  total++
  if (buf ~ /sk-ant-[A-Za-z0-9_-]+/ || buf ~ /ANTHROPIC_(API_KEY|AUTH_TOKEN)=[^[:space:]]+/) {
    hits++
    masked = mask(buf)
    if (ACTION == 1)      printf("  [deleted] %s\n", masked) > "/dev/stderr"
    else if (ACTION == 2) { printf("  [redacted] %s\n", masked) > "/dev/stderr"; print masked }
    else                  printf("  [match]   %s\n", masked) > "/dev/stderr"
  } else {
    print buf
  }
  buf = ""; seen = 0
}
{
  buf = seen ? buf ORS $0 : $0
  seen = 1
  if (trailing_bs($0) % 2 == 1) next   # multi-line entry: keep accumulating
  flush()
}
END {
  flush()
  printf("%d\t%d\n", hits + 0, total + 0) > "/dev/stderr"
}
'

# ---- run -----------------------------------------------------------------
stamp=$(date +%Y%m%d-%H%M%S)
grand_hits=0
modified=()

for f in $targets; do
  print "→ $f"
  errfile=$(mktemp) || exit 1
  outfile=$(mktemp) || exit 1
  chmod 600 "$outfile"

  # macOS awk chokes on the metafied bytes zsh writes for non-ASCII; treat as bytes.
  if ! LC_ALL=C awk -v ACTION="$action" "$scrub_awk" "$f" >"$outfile" 2>"$errfile"; then
    print -u2 "  ! awk failed on $f — left untouched"
    rm -f "$outfile" "$errfile"; continue
  fi

  summary=$(tail -n1 "$errfile")
  hits=${summary%%$'\t'*}
  total=${summary##*$'\t'}
  # A malformed summary must not silently read as "no hits".
  if [[ ! $hits =~ '^[0-9]+$' || ! $total =~ '^[0-9]+$' ]]; then
    print -u2 "  ! unreadable summary for $f — left untouched"
    rm -f "$outfile" "$errfile"; continue
  fi
  # show matched entries (everything but the trailing summary line)
  sed '$d' "$errfile" >&2

  grand_hits=$(( grand_hits + hits ))
  if (( hits == 0 )); then
    print "  clean ($total entries)"
    rm -f "$outfile" "$errfile"; continue
  fi

  if (( action == 0 )); then
    print "  $hits of $total entries contain a key — rerun with --clean to remove"
    rm -f "$outfile" "$errfile"; continue
  fi

  cp -p "$f" "$f.bak.$stamp"
  chmod 600 "$f.bak.$stamp"
  cat "$outfile" >"$f"          # preserves original inode + perms
  rm -f "$outfile" "$errfile"
  (( redact )) && verb=redacted || verb=removed
  print "  $hits entries $verb; backup: $f.bak.$stamp"
  modified+=("$f")
done

# ---- aftercare -----------------------------------------------------------
print ""
if (( grand_hits == 0 )); then
  print "No Anthropic keys found."
  exit 0
fi

if (( action == 0 )); then
  print "Dry run — nothing changed. Rerun with --clean."
  exit 1
fi

cat <<'EOS'
Done. Three things still matter:

1. ROTATE THE KEY. It was on disk in plaintext and is in the .bak file too.
   Revoke it at https://console.anthropic.com/settings/keys, then delete the
   backups once you have verified the history file looks right:
       rm ~/.zsh_history.bak.*

2. Other open shells still hold the old entries in memory and will write them
   back when they exit. Close them, or in each one run:
       unset HISTFILE; exec zsh

3. Seal the new key instead of pasting it into a command line again:
       touchseal set anthropic-api-key
   TouchSeal reads it from the terminal with echo disabled and never accepts a
   secret as an argument, so it cannot reach your history in the first place.
EOS
