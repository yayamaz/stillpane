#!/bin/bash
# stillpane PreToolUse hook for Claude Code.
# Approves Read calls inside ~/.claude/stillpane/ so an attached capture opens
# with no permission prompt. Every other path gets exit 0 with no output,
# which Claude Code treats as "no opinion": the normal permission flow runs.
set -eu

input=$(cat)

# A ".." anywhere could carry a path that starts under the capture root back
# out of it; never approve one.
case "$input" in *..*) exit 0 ;; esac

# The current hook payload is compact JSON; the spaced variant is matched too
# so an upstream formatting change fails toward prompting, not toward
# approving the wrong thing.
root="$HOME/.claude/stillpane/"

# A syntactically in-root path must not be auto-approved through a symlinked
# root, which would extend the approval to wherever the link points.
if [ -L "${root%/}" ]; then exit 0; fi

case "$input" in
  *"\"file_path\":\"$root"* | *"\"file_path\": \"$root"*) ;;
  *) exit 0 ;;
esac

# The decision is made on the exact field the Read tool acts on -
# .tool_input.file_path, parsed as JSON - never on a pattern that another
# occurrence of "file_path" in the payload could satisfy. A lexically in-root
# path can still resolve elsewhere through a symlinked capture directory or
# file, so approve only when the canonical path stays under the canonical
# root; anything unparseable or unresolvable falls through to the normal
# prompt. Absolute tool paths, because this hook inherits the caller's PATH.
path=$(printf '%s' "$input" | /usr/bin/plutil -extract tool_input.file_path raw -o - - 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
resolved=$(/usr/bin/readlink -f -- "$path" 2>/dev/null) || exit 0
canonical_root=$(/usr/bin/readlink -f -- "${root%/}" 2>/dev/null) || exit 0
case "$resolved" in
  "$canonical_root/"*)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"stillpane capture data"}}\n'
    ;;
esac
