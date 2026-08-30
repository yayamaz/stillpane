#!/bin/bash
# Tests for hooks/hook.sh and hooks/allow-read.sh, in plain Bash.
# Run from anywhere: bash Tests/HookTests.sh
#
# Every test runs against an isolated temporary HOME, so real captures are
# never read or touched. Runs under BSD and GNU userlands alike, because the
# hook itself must: the plugin installs on any machine running Claude Code,
# app or no app. The one environmental dependency is the hook's
# /Applications/stillpane.app check: the install-offer branch runs where the
# app is absent (CI), and the app-installed branch runs where it is present
# (a development machine), so each environment exercises its reachable side.
set -u

repo="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo/hooks/hook.sh"
allow="$repo/hooks/allow-read.sh"
app_installed=0
[ -d "/Applications/stillpane.app" ] && app_installed=1

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
    printf 'FAIL %s\n' "$1"
    failures=$((failures + 1))
}
assert_true() { # name, then the test command that must succeed
    name=$1
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}
assert_eq() { # name expected actual
    if [ "$2" = "$3" ]; then pass "$1"; else
        fail "$1"
        printf '     expected: %s\n     actual:   %s\n' "$2" "$3"
    fi
}

mode() { # octal permissions, BSD stat first, GNU fallback
    m=$(stat -f %Lp "$1" 2>/dev/null) || m=$(stat -c %a "$1")
    printf '%s\n' "$m"
}

cleanup_dirs=()
trap 'rm -rf "${cleanup_dirs[@]}"' EXIT

# A fresh isolated HOME per test; the capture root is not created here
# because root creation belongs to the app, and one test asserts exactly
# that.
new_home() {
    HOME=$(mktemp -d "${TMPDIR:-/tmp}/stillpane-hooktest.XXXXXX")
    export HOME
    cleanup_dirs+=("$HOME")
    root="$HOME/.claude/stillpane"
}

# Creates the root the way the app would (0700, install-offer marker seeded
# so the discovery branch stays quiet regardless of the machine).
make_root() {
    mkdir -p "$root"
    chmod 700 "$root"
    touch "$root/.install-offered"
}

# One fresh capture with the delivery contract's context.md shape.
make_capture() {
    dir="$root/20990101-000000-testapp"
    mkdir -p "$dir"
    printf '%s\n%s\n' "capture context" "Screenshot: {{DIR}}/shot.png" > "$dir/context.md"
}

run_hook() { CLAUDE_CODE_ENTRYPOINT=cli bash "$hook"; }

# --- headless sessions consume nothing ---------------------------------------

new_home
make_root
make_capture
out=$(CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$hook")
assert_eq "headless session emits nothing" "" "$out"
assert_true "headless session consumes nothing" test ! -e "$dir/.delivered"

# --- nothing to deliver is silent --------------------------------------------

new_home
make_root
out=$(run_hook)
status=$?
assert_eq "no capture is silent" "" "$out"
assert_eq "no capture exits 0" "0" "$status"

if [ "$app_installed" = 1 ]; then
    new_home
    out=$(run_hook)
    status=$?
    assert_eq "absent root is silent" "" "$out"
    assert_eq "absent root exits 0" "0" "$status"
    assert_true "absent root is not created by the hook" test ! -e "$root"
else
    new_home
    out=$(run_hook)
    case "$out" in
        *stillpane-install*) pass "install offer is emitted once" ;;
        *) fail "install offer is emitted once" ;;
    esac
    assert_eq "install offer creates a private root" "700" "$(mode "$root")"
    assert_eq "install marker is owner-only" \
        "600" "$(mode "$root/.install-offered")"
    out=$(run_hook)
    assert_eq "install offer never repeats" "" "$out"
fi

# --- stale captures are silent -----------------------------------------------

new_home
make_root
make_capture
touch -t 202001010000 "$dir/context.md"
out=$(run_hook)
assert_eq "stale capture is silent" "" "$out"
assert_true "stale capture is not marked delivered" test ! -e "$dir/.delivered"

# --- fresh capture emits exactly once ----------------------------------------

new_home
make_root
make_capture
out=$(run_hook)
case "$out" in
    *"Screenshot: $dir/shot.png"*) pass "fresh capture emits with {{DIR}} expanded" ;;
    *) fail "fresh capture emits with {{DIR}} expanded" ;;
esac
assert_true "delivery is marked" test -e "$dir/.delivered"
assert_eq "delivered marker is owner-only" "600" "$(mode "$dir/.delivered")"
assert_true "claim is released after delivery" test ! -e "$dir/.delivering"
out=$(run_hook)
assert_eq "second prompt attaches nothing" "" "$out"

# --- two concurrent prompts deliver once -------------------------------------

# Repeated rounds, because a single race often lets the winner finish before
# the loser even starts; twenty starts make the claim itself do the work.
races_won=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    new_home
    make_root
    make_capture
    run_hook > "$HOME/a.out" &
    run_hook > "$HOME/b.out" &
    wait
    nonempty=0
    [ -s "$HOME/a.out" ] && nonempty=$((nonempty + 1))
    [ -s "$HOME/b.out" ] && nonempty=$((nonempty + 1))
    [ "$nonempty" = 1 ] && races_won=$((races_won + 1))
done
assert_eq "exactly one emitter in every concurrent round" "20" "$races_won"

# --- a failed emit stays retryable -------------------------------------------

new_home
make_root
make_capture
chmod 000 "$dir/context.md"
out=$(run_hook 2>/dev/null)
rc=$?
assert_eq "failed emit outputs nothing" "" "$out"
assert_true "failed emit exits nonzero so partial output is discarded" test "$rc" -ne 0
assert_true "failed emit is not marked delivered" test ! -e "$dir/.delivered"
assert_true "failed emit releases its claim" test ! -e "$dir/.delivering"
chmod 600 "$dir/context.md"
out=$(run_hook)
assert_true "the next prompt retries a failed emit" test -n "$out"

# --- markers cannot refresh capture age --------------------------------------

new_home
make_root
make_capture
touch -t 202001010000 "$dir/context.md"
touch "$dir/.delivering"
rm "$dir/.delivering"
touch "$dir"
out=$(run_hook)
assert_eq "marker and directory activity cannot refresh a stale capture" "" "$out"

# --- a symlinked root is rejected by both hooks ------------------------------

new_home
target=$(mktemp -d "${TMPDIR:-/tmp}/stillpane-hooktest-target.XXXXXX")
cleanup_dirs+=("$target")
mkdir -p "$HOME/.claude"
ln -s "$target" "$root"
dir="$root/20990101-000000-testapp"
mkdir -p "$dir"
printf 'capture context\n' > "$dir/context.md"
touch "$root/.install-offered"
out=$(run_hook)
assert_eq "hook stands down on a symlinked root" "" "$out"
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$dir/context.md" | bash "$allow")
assert_eq "allow-read stands down on a symlinked root" "" "$out"

# --- a permissive root is left untouched by the hook -------------------------

new_home
make_root
make_capture
chmod 755 "$root"
run_hook > /dev/null
assert_eq "the hook never re-permissions the root" "755" "$(mode "$root")"

# --- allow-read approves only exact in-root reads ----------------------------

new_home
make_root
make_capture
in_root="$dir/context.md"
# The approve path parses JSON with plutil; where plutil is absent the hook
# falls through to the normal permission prompt, so only the refusal side is
# assertable there.
if [ -x /usr/bin/plutil ]; then
    out=$(printf '{"tool_input":{"file_path":"%s"}}' "$in_root" | bash "$allow")
    case "$out" in
        *'"permissionDecision":"allow"'*) pass "in-root read is approved" ;;
        *) fail "in-root read is approved" ;;
    esac
    out=$(printf '{"tool_input":{"file_path": "%s"}}' "$in_root" | bash "$allow")
    case "$out" in
        *'"permissionDecision":"allow"'*) pass "spaced JSON variant is approved" ;;
        *) fail "spaced JSON variant is approved" ;;
    esac
else
    out=$(printf '{"tool_input":{"file_path":"%s"}}' "$in_root" | bash "$allow")
    assert_eq "in-root read falls through where plutil is absent" "" "$out"
fi
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$HOME/.ssh/id_ed25519" | bash "$allow")
assert_eq "outside-root read is not approved" "" "$out"
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$root/x/../../.ssh/id_ed25519" | bash "$allow")
assert_eq "dot-dot read is not approved" "" "$out"
out=$(printf '{"tool_input":{"file_path":"/etc/passwd"},"file_path":"%s"}' "$in_root" | bash "$allow")
assert_eq "a decoy in-root path cannot approve a different tool_input path" "" "$out"

# --- allow-read refuses in-root paths that resolve outside the root -----------

new_home
make_root
make_capture
secret=$(mktemp "${TMPDIR:-/tmp}/stillpane-hooktest-secret.XXXXXX")
cleanup_dirs+=("$secret")
printf 'secret\n' > "$secret"
ln -s "$secret" "$dir/text.md"
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$dir/text.md" | bash "$allow")
assert_eq "symlinked capture file is not approved" "" "$out"
ln -s "$(dirname "$secret")" "$root/20990101-000001-linkdir"
out=$(printf '{"tool_input":{"file_path":"%s"}}' \
    "$root/20990101-000001-linkdir/$(basename "$secret")" | bash "$allow")
assert_eq "file inside a symlinked capture dir is not approved" "" "$out"

# --- freshness survives GNU stat semantics ------------------------------------

# GNU coreutils reads `stat -f %m FILE` as filesystem mode with %m as a file
# operand: the call exits nonzero yet still prints FILE's status block to
# stdout. The BSD-first fallback must replace that captured output, never
# extend it. A PATH shim reproduces GNU behavior on either userland.
new_home
make_root
make_capture
shimdir=$(mktemp -d "${TMPDIR:-/tmp}/stillpane-hooktest-shim.XXXXXX")
cleanup_dirs+=("$shimdir")
cat > "$shimdir/stat" <<'SHIM'
#!/bin/bash
case "$1" in
-f) printf '  File: "/shim"\n    ID: 0 Namelen: 255    Type: ext2/ext3\n'
    echo "stat: cannot read file system information for '%m'" >&2
    exit 1 ;;
-c) [ "$2" = "%Y" ] || exit 1
    date +%s ;;
*) exit 1 ;;
esac
SHIM
chmod +x "$shimdir/stat"
out=$(CLAUDE_CODE_ENTRYPOINT=cli PATH="$shimdir:$PATH" bash "$hook" 2>/dev/null)
rc=$?
case "$out" in
    *"Screenshot: $dir/shot.png"*) pass "GNU stat semantics still deliver a fresh capture" ;;
    *) fail "GNU stat semantics still deliver a fresh capture" ;;
esac
assert_eq "GNU stat delivery exits 0" "0" "$rc"
assert_true "GNU stat delivery is marked" test -e "$dir/.delivered"

# --- an unparseable mtime never reaches the arithmetic ------------------------

# A stat flavor that exits 0 with non-numeric output must end the hook
# nonzero and quiet: arithmetic on junk would abort mid-script with the
# capture unclaimed, and exit 0 would silently discard it forever.
new_home
make_root
make_capture
cat > "$shimdir/stat" <<'SHIM'
#!/bin/bash
printf 'not an epoch\n'
SHIM
out=$(CLAUDE_CODE_ENTRYPOINT=cli PATH="$shimdir:$PATH" bash "$hook" 2>/dev/null)
rc=$?
assert_eq "non-numeric mtime outputs nothing" "" "$out"
assert_true "non-numeric mtime exits nonzero" test "$rc" -ne 0
assert_true "non-numeric mtime does not mark delivery" test ! -e "$dir/.delivered"

# --- the documented hooks are byte-identical to the shipped hooks -------------

# how-it-works.md promises its quoted hook blocks are verbatim; this is the
# check that keeps that promise from drifting when a hook changes.
doc="$repo/docs/how-it-works.md"
extract_block() { # prints the first fenced code block containing the marker
    awk -v sig="$1" '
        /^```/ {
            if (inblock) { if (found) { printf "%s", buf; exit }; inblock = 0 }
            else { inblock = 1; buf = ""; found = 0 }
            next
        }
        inblock { buf = buf $0 "\n"; if (index($0, sig)) found = 1 }
    ' "$doc"
}
if extract_block "UserPromptSubmit hook" | cmp -s - "$hook"; then
    pass "how-it-works quotes hook.sh byte-for-byte"
else
    fail "how-it-works quotes hook.sh byte-for-byte"
fi
if extract_block "PreToolUse hook" | cmp -s - "$allow"; then
    pass "how-it-works quotes allow-read.sh byte-for-byte"
else
    fail "how-it-works quotes allow-read.sh byte-for-byte"
fi

# ------------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
    printf '%d failure(s)\n' "$failures"
    exit 1
fi
printf 'all hook tests passed\n'
