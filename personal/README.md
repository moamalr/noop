# Personal setup

This fork builds NOOP for one iPhone under its own bundle ids and lets local agents (Claude Code,
Codex, OpenCode) read the WHOOP data it collects. Everything here is additive: upstream files are
untouched apart from the `noop-local-access` improvements, so `git merge upstream/main` stays easy.

## How the pieces fit

```
WHOOP strap ──BLE──▶ NOOP on iPhone ──devicectl copy──▶ snapshot on Mac ──MCP──▶ agents
                     (whoop.sqlite)   (USB or Wi-Fi)    (read-only)      (noop-mcp)
```

- **Build** — `.github/workflows/personal-ios.yml` compiles NOOPiOS unsigned on a GitHub macOS 26
  runner, so the Mac needs no DerivedData. `personal-mcp.yml` builds and tests `noop-local-access`.
- **Install** — `personal/bin/noop-install` downloads the newest iOS build, signs it with the Apple
  Development identity and the profiles from `noop-provision`, and installs it with `devicectl`.
- **Agents** — `personal/bin/noop-mcp` is the MCP server agents launch. It pulls a fresh copy of
  the phone's database (`noop-pull`) at start and every 15 minutes, and serves it read-only through
  `noop-local-access`. When the phone is away, agents get the last snapshot and `data_freshness`
  says how old it is.

## Identifiers

| | |
|---|---|
| Team | `66R42699RQ` |
| App | `com.moamalrassan.noop` |
| Widget | `com.moamalrassan.noop.widgets` |
| App Group | `group.com.moamalrassan.noop.staging` |

CI reads the prefix from the repository variable `BUNDLE_ID_PREFIX`; the scripts default to the
same values and accept overrides from the environment or `personal/config.local.env` (gitignored),
e.g. `NOOP_DEVICE=<name|udid>` to pick a phone.

## Everyday commands

```sh
personal/bin/noop-install          # newest CI build → iPhone
personal/bin/noop-pull             # refresh the agent snapshot now
personal/bin/noop-agent-setup      # reinstall the MCP binary and re-register agents
personal/bin/noop-provision        # renew profiles (new device, or yearly expiry)
```

To change the app: edit, push to `main`, wait for **Personal iOS** to go green
(`gh run watch -R moamalr/noop`), then `noop-install`.

## Asking agents

The `whoop` MCP server offers `health_snapshot`, `metric_series`, `sleep_summary`,
`workout_summary`, `heart_rate_series` and `data_freshness`, plus the prompts
`weekly_health_review`, `explain_recovery` and `debug_data_freshness`. Examples:

- "How did I sleep this week compared with the week before?"
- "What was my heart rate during this morning's run?"
- "Why might my recovery be low today?"

NOOP's in-app **AI Coach** also works on the phone with your own Anthropic, OpenAI, Gemini or local
OpenAI-compatible key.

## Notes

- The watch app is stripped at install time; it would need its own watchOS profiles.
- The development profile lasts a year. NOOP keeps running until it expires; `noop-provision` then
  `noop-install` renews it.
- `devicectl` can read the app's container only because the build is development-signed.
