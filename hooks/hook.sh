#!/bin/bash
# stillpane UserPromptSubmit hook for Claude Code.
# Emits the latest capture's context block exactly once, only while fresh.
# Exit 0 with no output is invisible to the user (per Claude Code hook docs).
# The capture root is fixed by the stillpane app; it is stillpane's data
# directory, not Claude Code config, so CLAUDE_CONFIG_DIR does not apply.
# The hook is a courier: it reads the newest capture and writes markers. The
# app owns the root - the hook never repairs its permissions and creates it
# only once, to leave the one-time install-offer marker on a machine that has
# the plugin but not the app.
set -eu

# Everything this hook writes - markers, claims - is owner-only.
umask 077

# Headless runs - claude -p and the Agent SDK - set CLAUDE_CODE_ENTRYPOINT to
# an sdk-* value. A script or scheduled job submitting a prompt within the
# freshness window would otherwise consume the capture meant for the user's
# interactive session.
case "${CLAUDE_CODE_ENTRYPOINT:-}" in sdk*) exit 0 ;; esac

root="$HOME/.claude/stillpane"

# A symlinked root could redirect marker writes wherever the link points.
if [ -L "$root" ]; then exit 0; fi

# Discovery, exactly once per machine: the plugin can be installed long before
# the app (plugin-first install path). Surface the gap a single time and never
# again - the marker outlives captures because pruning only touches the
# timestamped capture directories.
if [ ! -d "/Applications/stillpane.app" ] && [ ! -e "$root/.install-offered" ]; then
    mkdir -p "$root"
    touch "$root/.install-offered"
    printf '%s\n' "Note: the stillpane plugin is installed, but the stillpane menu bar app is not in /Applications, so nothing can be captured yet. If it fits the conversation, briefly offer to install it via the stillpane-install skill (it downloads the latest release and installs only a notarized build signed by stillpane's Developer ID). Do not repeat this offer."
fi

# An absent root means nothing to deliver; the app creates it, not the hook.
[ -d "$root" ] || exit 0

latest=$(find "$root" -mindepth 1 -maxdepth 1 -type d -name '20*' 2>/dev/null | sort | tail -1)
[ -n "$latest" ] || exit 0
[ -e "$latest/.delivered" ] && exit 0
[ -f "$latest/context.md" ] || exit 0

# Freshness comes from context.md, written once at capture time: claim and
# marker writes change the directory's own timestamps and must never extend
# the two-minute window. GNU stat reads `-f %m` as filesystem mode with a %m
# file operand: the call fails yet still prints the file's status block, so
# the fallback must replace what the first branch captured, never extend it.
# A non-numeric mtime would abort the arithmetic mid-script; refuse it
# explicitly instead, nonzero so the miss is visible rather than silently
# discarding the capture.
now=$(date +%s)
born=$(stat -f %m "$latest/context.md" 2>/dev/null) \
    || born=$(stat -c %Y "$latest/context.md")
case "$born" in '' | *[!0-9]*) exit 1 ;; esac
[ $((now - born)) -le 120 ] || exit 0

# Atomic claim: two prompts arriving together would both pass the .delivered
# check above, and the O_EXCL create succeeds for exactly one of them. The
# noclobber redirect keeps the exclusive open inside bash itself: an external
# mkdir can be a non-atomic reimplementation (uutils coreutils races its
# existence check against concurrent callers). The loser exits silently.
# HUP/INT/TERM exit through the EXIT trap, which releases the claim.
# Deliberately no stale-claim reaping: reaping on a timer could duplicate a
# merely slow emitter, so an untrappable kill during the tiny emission window
# forfeits auto-delivery for that one capture instead - /stillpane still
# attaches it.
claim="$latest/.delivering"
(set -C; : > "$claim") 2>/dev/null || exit 0
trap 'rm -f "$claim" 2>/dev/null || true' EXIT
# Nonzero, so a signal landing mid-emit discards the partial block - Claude
# Code only injects a hook's stdout on exit 0 - and the capture stays
# retryable because the delivered marker was never written.
trap 'exit 1' HUP INT TERM

# The prompt that won the race between our check and our claim may already
# have delivered.
[ -e "$latest/.delivered" ] && exit 0

# Pure-bash substitution: a path containing & or | would corrupt sed's
# replacement. Mark delivered only after the emit actually succeeds, so a
# failed emit stays retryable on the next prompt. The status check is
# explicit because a failed redirection on a compound command does not trip
# set -e, and the exit is nonzero because a read failing mid-file would
# leave partial output - possibly an unclosed untrusted envelope - and
# Claude Code injects stdout only on exit 0.
while IFS= read -r line; do printf '%s\n' "${line//"{{DIR}}"/$latest}"; done \
    < "$latest/context.md" || exit 1
touch "$latest/.delivered"
