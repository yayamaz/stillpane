---
name: stillpane-install
description: Install the stillpane menu bar app when it is missing from /Applications - downloads the latest release, verifies it is a notarized build signed by stillpane's Developer ID, installs, and launches its setup assistant
---

The stillpane plugin is running, but captures need the stillpane menu bar app in /Applications. This skill installs it.

1. Confirm with the user that they want `stillpane.app` downloaded from the latest GitHub release and installed to /Applications. Never run the script without that confirmation.
2. Run the `install-app.sh` that sits in this skill's directory (next to this SKILL.md): `bash "<this skill's directory>/install-app.sh"`.
3. The script hard-fails unless the download is a notarized app signed under stillpane's own bundle identifier and Apple Developer Team ID - Gatekeeper assessment first, then the pinned signing requirement. If either check fails, report the script's output to the user and stop. Never bypass, retry around, or substitute those checks - a rejected download must not be installed by any means.
4. On success the app launches and opens its own setup assistant. Tell the user to follow it (grant Accessibility; Screen Recording is optional), and that captures only attach in Claude Code sessions started after setup completes.
