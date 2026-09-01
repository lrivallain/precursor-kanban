# Security Policy

## Threat model

`precursor-kanban` is a plugin loaded **inside** a running Precursor process. It
has no process, port or storage of its own, and inherits Precursor's model
entirely: single-user, local-first, no authentication, bound to `127.0.0.1`.
Anyone who can reach the app can reach this plugin.

What the plugin adds to that surface:

- **A GitHub token is used, never stored.** The board reads the token Precursor
  already resolved and calls the GitHub GraphQL API with it. Nothing is
  persisted here and no credential is returned by its endpoints.
- **The `project` scope is required**, which is broader than the board needs to
  *read*: with it, the plugin's drag-and-drop endpoint can also **write** —
  `updateProjectV2ItemFieldValue` moves a card between columns for real, on
  GitHub.
- **Its endpoints are gated by the host**, behind the same "issue associations"
  switch and repository guards as the rest of Precursor's GitHub surface. They
  answer 403 when it is off.
- **The MCP server (`kanban.board`) is read-only** and runs as a stdio
  subprocess of the app, sharing its database and credentials.
- **The frontend bundle executes in the app's page** with the app's own React.
  That is inherent to the plugin contract: install a plugin only if you trust
  its publisher.

## Supported versions

Pre-1.0, CalVer (`YYYY.M.MICRO`). Only the **latest** release is supported;
fixes ship in a new release rather than as backports.

## Reporting a vulnerability

Please **do not** open a public issue for security reports.

Use GitHub's [private vulnerability reporting](https://github.com/lrivallain/precursor-kanban/security/advisories/new)
for this repository. Include a description, reproduction steps, the plugin
version and the Precursor version it was running under (**Settings → Plugins**
shows both). We aim to acknowledge reports within a few days.

If the issue is in Precursor itself rather than this plugin, report it
[there](https://github.com/lrivallain/precursor/security/advisories/new) instead.
