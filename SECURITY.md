# Security Policy

stillpane captures screenshots and window text, so security reports get priority attention.

## Reporting a vulnerability

Use [GitHub's private vulnerability reporting](../../security/advisories/new) on this repository, or email hello@stillpane.dev if you prefer to stay off GitHub.
Do not open a public issue for anything exploitable: captures can contain credentials, and a public report puts users at risk before a fix exists.

You will get an acknowledgment within a few days, and credit in the fix's release notes unless you prefer otherwise.

## Scope worth knowing about

The security-relevant design decisions - what a capture can contain, why capture text is delimited as untrusted input, and why the permission hook's auto-approval is scoped to `~/.claude/stillpane/` alone - are documented in [`docs/how-it-works.md`](docs/how-it-works.md).
Reports that those mitigations can be bypassed are exactly what private reporting is for.
