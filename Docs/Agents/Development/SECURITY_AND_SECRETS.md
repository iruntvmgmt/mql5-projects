# Security and Secrets Policy

## Purpose

Protect credentials, broker access, MCP tokens, repository integrity, account state, and proprietary trading research while allowing autonomous agents to compile and test safely.

## Secrets

Secrets include:

- MCP bearer tokens;
- broker credentials and account identifiers;
- API keys;
- GitHub tokens;
- SSH keys;
- private endpoints;
- notification credentials;
- prop-firm login data;
- encrypted or plaintext terminal configuration that permits account access.

Never commit, quote, summarize, log, or reproduce a secret in Markdown, source, ticket, evidence, chat output, commit message, or pull request.

Use environment variables or approved local untracked files. Scripts must fail closed when a required secret is absent.

## Tracked-secret response

When a secret is found in a tracked file or history:

1. stop printing or copying it;
2. report the file and secret class without reproducing the value;
3. recommend immediate rotation;
4. replace usage with an environment variable or local untracked configuration;
5. determine whether history cleanup is required;
6. do not claim the secret is safe merely because the repository is private or obscure.

## Least privilege

Each agent receives only the tools and filesystem scope required by its role.

- Strategy agents do not receive deployment credentials.
- Reviewers do not receive write permission.
- Runtime agents do not receive authority to change strategy semantics.
- Research agents do not receive broker mutation authority.
- Lead agents do not receive automatic merge or live-deployment authority.

## Broker and terminal safety

Agents may perform read-only health and account-state inspection when authorized. They may not:

- place, cancel, modify, or close broker orders;
- attach an EA to a live chart;
- enable Algo Trading for live operation;
- change account or server configuration;
- regenerate or expose tokens;
- disable protective controls;
- adopt unknown positions.

Strategy Tester and isolated runtime tasks must use explicit configs and must not rely on a live chart attachment.

## File safety

- Preserve inherited uncommitted work.
- Do not delete or overwrite logs and outputs without task-specific quarantine.
- Do not copy test harnesses into the main terminal as an undocumented fallback.
- Do not run recursive formatting or cleanup across unrelated projects.
- Verify destination paths before file operations involving spaces or Wine prefixes.

## Dependency and command safety

- Do not install packages, extensions, MCP servers, or executables without approval.
- Do not execute downloaded scripts without inspection.
- Prefer repository-pinned or standard-library dependencies.
- Record commands that change the environment.
- Never use `curl | sh`, unverified binaries, or broad destructive shell commands.

## Research confidentiality

Treat strategy specifications, parameter sets, journals, results, and architecture as project intellectual property. Do not publish them externally, upload them to unrelated services, or include them in public issues unless explicitly authorized.

## Incident report

A security incident report must include:

- time detected;
- affected file/system;
- incident class;
- exposure scope;
- actions taken;
- rotation or revocation status;
- remaining risk;
- exact next action.

Do not include the exposed value itself.
