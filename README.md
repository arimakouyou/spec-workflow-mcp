# Spec Workflow MCP

[![npm version](https://img.shields.io/npm/v/@arimakouyou/spec-workflow-mcp)](https://www.npmjs.com/package/@arimakouyou/spec-workflow-mcp)
[![VSCode Extension](https://vsmarketplacebadges.dev/version-short/arimakouyou.spec-workflow-mcp.svg)](https://marketplace.visualstudio.com/items?itemName=arimakouyou.spec-workflow-mcp)

A Model Context Protocol (MCP) server for structured spec-driven development with real-time dashboard and VSCode extension.

## ☕ Support This Project

<a href="https://buymeacoffee.com/arimakouyou" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## 📺 Showcase

### 🔄 Approval System in Action
<a href="https://www.youtube.com/watch?v=C-uEa3mfxd0" target="_blank">
  <img src="https://img.youtube.com/vi/C-uEa3mfxd0/maxresdefault.jpg" alt="Approval System Demo" width="600">
</a>

> See how the approval system works: create documents, request approval through the dashboard, provide feedback, and track revisions.

### 📊 Dashboard & Spec Management
<a href="https://www.youtube.com/watch?v=g9qfvjLUWf8" target="_blank">
  <img src="https://img.youtube.com/vi/g9qfvjLUWf8/maxresdefault.jpg" alt="Dashboard Demo" width="600">
</a>

> Explore the real-time dashboard: view specs, track progress, navigate documents, and monitor your development workflow.

## ✨ Key Features

- **Structured Development Workflow** - Sequential spec creation (Request Spec → Requirements → Design → Test Design → Tasks)
- **Real-Time Web Dashboard** - Monitor specs, tasks, and progress with live updates
- **Rich Markdown Preview** - Render Mermaid diagrams as SVG in dashboard document and review previews
- **VSCode Extension** - Integrated sidebar dashboard for VSCode users
- **Approval Workflow** - Complete approval process with revisions
- **Task Progress Tracking** - Visual progress bars and detailed status
- **Implementation Logs** - Searchable logs of all task implementations with code statistics
- **CI/CD Generation** - `/setup-ci` generates 5 GitHub Actions workflow files (ci, e2e, scheduled-quality, dependabot, release)

## 🚀 Quick Start

### Option 1: Claude Code Plugin (Recommended for Claude Code users)

Install directly as a Claude Code plugin — skills, agents, rules, hooks, and MCP server are all configured automatically:

```bash
claude plugin add --from https://github.com/arimakouyou/spec-workflow-mcp
```

> **What the plugin includes:**
>
> - **MCP server** for spec-driven development workflow
> - **50+ skills** covering the full spec lifecycle (request-spec → requirements → design → test-design → tasks → implement → archive) plus integration testing (Rust / .NET), TDD, CI generation, mutation testing, arch test generation, PR comment handling, and more
> - **6 specialized sub-agents** organized as Implementer (parallel-worker / unit-test-engineer / frontend-test-engineer / integ-test-worker) and Reviewer (review-worker / integ-test-auditor) roles, with **multi-language support** (Rust + .NET via `Language:` argument)
> - **17 rules** covering project architecture, QC1-QC13 quality checks, OWASP security, design principles, type safety (TS-R1-R5 / TS-C1-C5), failure taxonomy (FC1-FC6), and L1-L5 enforcement levels with promotion criteria
> - **16 hooks** for spec injection, test verification, design conformance check, arch test regeneration, build cache, diff-aware security audit, and phase progression confirmation
> - **Helper scripts** for implementation session management (`session-manage.sh`) and rate-limit auto-resume wrapper (`auto-resume.sh`)

> **Prerequisites for the plugin hooks:**
>
> - `jq` — required by every hook for JSON parsing
> - GNU coreutils (`timeout`) — required by `security-audit-guard.sh` for fail-close audit timeouts (preinstalled on Linux; install via `brew install coreutils` on macOS)
>
> These utilities are only required when the plugin hooks run; the MCP server and web dashboard do not depend on them.

### Option 2: Manual MCP Configuration

Add to your MCP configuration (see client-specific setup below):

```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```

### Step 2: Choose your interface

**Option A: Web Dashboard** (Required for CLI users)
Start the dashboard (runs on port 5000 by default):
```bash
npx -y @arimakouyou/spec-workflow-mcp@latest --dashboard
```

The dashboard will be accessible at: http://localhost:5000

> **Note:** Only one dashboard instance is needed. All your projects will connect to the same dashboard.

**Option B: VSCode Extension** (Recommended for VSCode users)

Install [Spec Workflow MCP Extension](https://marketplace.visualstudio.com/items?itemName=arimakouyou.spec-workflow-mcp) from the VSCode marketplace.

## 📝 How to Use

Simply mention spec-workflow in your conversation:

- **"Create a spec for user authentication"** - Creates complete spec workflow
- **"List my specs"** - Shows all specs and their status
- **"Execute task 1.2 in spec user-auth"** - Runs a specific task

[See more examples →](docs/PROMPTING-GUIDE.md)

## 🔧 MCP Client Setup

<details>
<summary><strong>Augment Code</strong></summary>

Configure in your Augment settings:
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Claude Code CLI</strong></summary>

Add to your MCP configuration:
```bash
claude mcp add spec-workflow npx @arimakouyou/spec-workflow-mcp@latest -- /path/to/your/project
```

**Important Notes:**
- The `-y` flag bypasses npm prompts for smoother installation
- The `--` separator ensures the path is passed to the spec-workflow script, not to npx
- Replace `/path/to/your/project` with your actual project directory path

**Alternative for Windows (if the above doesn't work):**
```bash
claude mcp add spec-workflow cmd.exe /c "npx @arimakouyou/spec-workflow-mcp@latest /path/to/your/project"
```
</details>

<details>
<summary><strong>Claude Desktop</strong></summary>

Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```

> **Important:** Run the dashboard separately with `--dashboard` before starting the MCP server.

</details>

<details>
<summary><strong>Cline/Claude Dev</strong></summary>

Add to your MCP server configuration:
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Continue IDE Extension</strong></summary>

Add to your Continue configuration:
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Cursor IDE</strong></summary>

Add to your Cursor settings (`settings.json`):
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>OpenCode</strong></summary>

Add to your `opencode.json` configuration file:
```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "spec-workflow": {
      "type": "local",
      "command": ["npx", "-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"],
      "enabled": true
    }
  }
}
```
</details>

<details>
<summary><strong>Windsurf</strong></summary>

Add to your `~/.codeium/windsurf/mcp_config.json` configuration file:
```json
{
  "mcpServers": {
    "spec-workflow": {
      "command": "npx",
      "args": ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
    }
  }
}
```
</details>

<details>
<summary><strong>Codex</strong></summary>

Add to your `~/.codex/config.toml` configuration file:
```toml
[mcp_servers.spec-workflow]
command = "npx"
args = ["-y", "@arimakouyou/spec-workflow-mcp@latest", "/path/to/your/project"]
```
</details>

## 🐳 Docker Deployment

Run the dashboard in a Docker container for isolated deployment:

```bash
# Using Docker Compose (recommended)
cd containers
docker-compose up --build

# Or using Docker CLI
docker build -f containers/Dockerfile -t spec-workflow-mcp .
docker run -p 5000:5000 -v "./workspace/.spec-workflow:/workspace/.spec-workflow:rw" spec-workflow-mcp
```

The dashboard will be available at: http://localhost:5000

[See Docker setup guide →](containers/README.md)

## 🔒 Security

Spec-Workflow MCP includes enterprise-grade security features suitable for corporate environments:

### ✅ Implemented Security Controls

| Feature | Description |
|---------|-------------|
| **Localhost Binding** | Binds to `127.0.0.1` by default, preventing network exposure |
| **Rate Limiting** | 120 requests/minute per client with automatic cleanup |
| **Audit Logging** | Structured JSON logs with timestamp, actor, action, and result |
| **Security Headers** | X-Content-Type-Options, X-Frame-Options, X-XSS-Protection, CSP, Referrer-Policy |
| **CORS Protection** | Restricted to localhost origins by default |
| **Docker Hardening** | Non-root user, read-only filesystem, dropped capabilities, resource limits |

### ⚠️ Not Yet Implemented

| Feature | Workaround |
|---------|------------|
| **HTTPS/TLS** | Use a reverse proxy (nginx, Apache) with TLS certificates |
| **User Authentication** | Use a reverse proxy with Basic Auth or OAuth2 Proxy for SSO |

### For External/Network Access

If you need to expose the dashboard beyond localhost, we recommend:

1. **Keep dashboard on localhost** (`127.0.0.1`)
2. **Use nginx or Apache** as a reverse proxy with:
   - TLS/HTTPS termination
   - Basic authentication or OAuth2
3. **Configure firewall rules** to restrict access

```nginx
# Example nginx reverse proxy with auth
server {
    listen 443 ssl;
    server_name dashboard.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    auth_basic "Dashboard Access";
    auth_basic_user_file /etc/nginx/.htpasswd;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

[See Docker security guide →](containers/README.md#security-configuration)

## 🔒 Sandboxed Environments

For sandboxed environments (e.g., Codex CLI with `sandbox_mode=workspace-write`) where `$HOME` is read-only, use the `SPEC_WORKFLOW_HOME` environment variable to redirect global state files to a writable location:

```bash
SPEC_WORKFLOW_HOME=/workspace/.spec-workflow-mcp npx -y @arimakouyou/spec-workflow-mcp@latest /workspace
```

[See Configuration Guide →](docs/CONFIGURATION.md#environment-variables)

## 📚 Documentation

- [Configuration Guide](docs/CONFIGURATION.md) - Command-line options, config files
- [User Guide](docs/USER-GUIDE.md) - Comprehensive usage examples
- [Workflow Process](docs/WORKFLOW.md) - Development workflow and best practices
- [Interfaces Guide](docs/INTERFACES.md) - Dashboard and VSCode extension details
- [Prompting Guide](docs/PROMPTING-GUIDE.md) - Advanced prompting examples
- [Tools Reference](docs/TOOLS-REFERENCE.md) - Complete tools documentation
- [Development](docs/DEVELOPMENT.md) - Contributing and development setup
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 📁 Project Structure

### Working Directory (per project)

```
your-project/
  .spec-workflow/
    approvals/
    archive/
    specs/
    steering/
    templates/
    user-templates/
    config.example.toml
```

### Plugin Structure (distributed via `.claude-plugin/`)

```text
.claude-plugin/
  plugin.json              # Plugin manifest
  marketplace.json         # Marketplace listing
  .mcp.json                # MCP server configuration

  hooks/                   # 16 event-driven hooks
    hooks.json             # Hook registrations (PreToolUse / PostToolUse / Stop / SessionStart / UserPromptSubmit)
    inject-spec.sh         # UserPromptSubmit: spec context injection
    inject-skill-hint.sh   # PreToolUse Edit|Write: skill discovery hint
    inject-build-cache.sh  # PreToolUse Bash: cargo / dotnet build cache hint
    lockfile-guard.sh      # PreToolUse Bash: lockfile integrity guard
    format-check-guard.sh  # PreToolUse Bash: format check
    security-audit-guard.sh # PreToolUse Bash: diff-aware security audit (fail-close)
    post-edit.sh           # PostToolUse Edit|Write: post-edit formatter
    auto-verify-spec.sh    # PostToolUse Edit|Write: spec consistency check
    detect-new-files.sh    # PostToolUse Write: orphan file detection
    design-conformance-check.sh  # PostToolUse Edit|Write: design.md vs code drift
    module-boundary-check.sh     # PostToolUse Edit|Write: module boundary violation check
    arch-test-regen-hint.sh      # PostToolUse Edit|Write: arch test regeneration prompt
    verify-tests-run.sh    # Stop: test runner execution check
    log-implementation.sh  # Stop: implementation log skeleton auto-generation
    confirm-phase-progression.sh # Stop: phase progression consent check
    resume-hint.sh         # SessionStart: resume context injection

  scripts/                 # Helper scripts (user-invokable)
    session-manage.sh      # Implementation session state manager
    auto-resume.sh         # Rate-limit auto-resume wrapper (claude --print loop)

  skills/                  # 50+ skills (excerpt below)
    spec-request-spec/     # Request spec creation
    spec-requirements/     # Requirements creation
    spec-design/           # Design document creation
    spec-test-design/      # Test design creation
    spec-tasks/            # Task breakdown
    spec-implement/        # Implementation workflow (Orchestrator)
    spec-review/           # Code review
    spec-archive/          # Auto-archive completed specs
    integration-test/      # Rust integration testing
    integration-test-dotnet/ # .NET integration testing
    tdd-skills/            # TDD workflow
    tdd-skills-rust/       # Rust TDD patterns
    tdd-skills-dotnet/     # .NET TDD patterns (xUnit + NSubstitute / Moq)
    cargo-mutants/         # Mutation testing
    setup-ci/              # GitHub Actions CI generation (5 base + optional add-ons)
    generate-arch-tests/   # Architecture test generation (L4 structural)
    handle-pr-comments/    # PR review response
    knowhow-capture/       # Knowledge capture
    feedback-loop/         # Failure → rule promotion / demotion loop
  agents/                  # 6 specialized sub-agents
    parallel-worker.md         # TDD core (Implementer; launched serially per `rules/serial-execution-policy.md`)
    unit-test-engineer.md      # Unit test engineer (Rust + C#/.NET)
    frontend-test-engineer.md  # Leptos frontend test engineer
    integ-test-worker.md       # Integration test (Rust + .NET via Language: argument)
    integ-test-auditor.md      # Integration test auditor (Rust + .NET, read-only L3)
    review-worker.md           # Code review + commit + Phase Review (Reviewer)

  rules/                   # 18 rules
    quality-checks.md      # QC1-QC13 quality enforcement (lint / test / coverage / mutation)
    enforcement-levels.md  # L1-L5 model + promotion / demotion criteria
    security.md            # OWASP Top 10 + auth/authz
    design-principles.md   # SOLID + dependency direction
    design-conformance.md  # Prevent drift from approved design.md
    type-safety.md         # TS-R1-R5 (Rust) + TS-C1-C5 (C#)
    failure-taxonomy.md    # FC1-FC6 cross-worker failure vocabulary
    diagnostic-reasoning.md # DR1-DR6 retry / divergent thinking protocol
    serial-execution-policy.md # All subagent launches are serial-only
    ...                    # 18 rules total
```

## 🛠️ Development

```bash
# Install dependencies
npm install

# Build the project
npm run build

# Run in development mode
npm run dev
```

[See development guide →](docs/DEVELOPMENT.md)

## 📄 License

GPL-3.0

## ⭐ Star History

<a href="https://www.star-history.com/#arimakouyou/spec-workflow-mcp&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=arimakouyou/spec-workflow-mcp&type=Date" />
 </picture>
</a>
