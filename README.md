# Spec Workflow MCP

[![npm version](https://img.shields.io/npm/v/@arimakouyou/spec-workflow-mcp)](https://www.npmjs.com/package/@arimakouyou/spec-workflow-mcp)

A Model Context Protocol (MCP) server for structured spec-driven development with real-time dashboard.

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

- **Structured Development Workflow** - Sequential spec creation (Steering → Request Spec → Requirements → Design → Test Design), with tasks generated from the approved documents
- **Single Source of Truth per Fact** - Every name, signature, path and test case is owned by exactly one document; other documents refer to it by ID, and a deterministic lint enforces it
- **Approval Ledger** - Re-approving an upstream document makes downstream approvals stale automatically
- **Real-Time Web Dashboard** - Monitor specs, tasks, and progress with live updates
- **Rich Markdown Preview** - Render Mermaid diagrams as SVG in dashboard document and review previews
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
> - **MCP server** with the `approvals` tool and the approval ledger (`@arimakouyou/spec-workflow-mcp@^3`; the v2 workflow does not work with a 2.x server, which writes no ledger)
> - **Spec workflow skills**: steering-doc, spec-request-spec, spec-investigate, spec-requirements, spec-design, spec-test-design, spec-review, check-approval, spec-change, spec-implement, spec-status, spec-archive, plus TDD / integration-test procedures and framework references (Rust / .NET)
> - **8 sub-agents**: spec-author / spec-reviewer (documents), impl-worker / integ-test-worker (implementation), unit-test-engineer / frontend-test-engineer / integ-test-auditor (read-only verification), review-worker (the only committer)
> - **Deterministic scripts** (Bash): document lint (`spec-lint.sh`), signature compile check (`spec-sigcheck.sh`), task generation (`spec-plan.sh`), briefs, the commit gate (`spec-git.sh`, G0-G9), reopen after spec changes
> - **Hooks** that enforce the flow with exit 2: guard-edit, guard-git, guard-agent, guard-approval-request, record-subagent, stop-failure, session-start
>
> See [PLUGIN_FLOWS.ja.md](PLUGIN_FLOWS.ja.md) for the whole flow.

> **Prerequisites for the plugin scripts and hooks:** `bash`, `jq`, `gawk`, `sha256sum`, `git`; `cargo` for the Rust signature check. The MCP server and web dashboard do not depend on them.

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

### Step 2: Choose Interface (Web Dashboard)
Start the dashboard (runs on port 5000 by default):
```bash
npx -y @arimakouyou/spec-workflow-mcp@latest --dashboard
```

The dashboard will be accessible at: http://localhost:5000

> **Note:** Only one dashboard instance is needed. All your projects will connect to the same dashboard.

## 📝 How to Use

With the Claude Code plugin:

- **`/steering-doc`** - Create the project steering documents (first time only)
- **`/spec-request-spec`** - Start a new spec; each approved document leads to the next phase automatically (`/check-approval` after approving in the dashboard)
- **`/spec-implement <spec>`** - Implement the approved spec task by task
- **`/spec-change <spec>`** - Change an approved document; downstream documents and affected tasks follow
- **`/spec-status <spec>`** - Show document states and progress

The full flow is described in [PLUGIN_FLOWS.ja.md](PLUGIN_FLOWS.ja.md).

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
- [Interfaces Guide](docs/INTERFACES.md) - Dashboard details
- [Prompting Guide](docs/PROMPTING-GUIDE.md) - Advanced prompting examples
- [Tools Reference](docs/TOOLS-REFERENCE.md) - Complete tools documentation
- [Development](docs/DEVELOPMENT.md) - Contributing and development setup
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 📁 Project Structure

### Working Directory (per project)

```
your-project/
  .spec-workflow/
    approvals/<spec>/ledger.json   # approval ledger (written by the MCP server only)
    approvals/<spec>/content/      # approved document contents by sha256
    archive/specs/
    specs/<spec>/                  # request-spec, requirements, design, test-design, tasks (generated), evidence/, task-logs/
    steering/                      # product.md, tech.md, structure.md
```

### Plugin Structure (distributed via `.claude-plugin/`)

```text
.claude-plugin/
  plugin.json              # Plugin manifest
  marketplace.json         # Marketplace listing
  .mcp.json                # MCP server configuration

  hooks/                   # Enforcement hooks (exit 2) and session context
    hooks.json
    session-start.sh       # SessionStart: implementation state and next task
    guard-edit.sh          # PreToolUse Edit|Write: approved documents, generated files, ledger
    guard-git.sh           # PreToolUse Bash: commits only through spec-git.sh
    guard-agent.sh         # PreToolUse Agent: one agent at a time, task/agent mapping, order
    guard-approval-request.sh # PreToolUse approvals: lint + sigcheck before a request
    record-subagent.sh     # SubagentStop: record the agent's final JSON
    stop-failure.sh        # StopFailure: record interruptions for resume
    post-edit.sh           # PostToolUse Edit|Write: formatter

  scripts/                 # Deterministic Bash tools
    spec-lint.sh           # Document lint (L01-L26)
    spec-sigcheck.sh       # Compile the design's signatures (Rust)
    spec-state.sh          # Document states from the approval ledger
    spec-plan.sh           # Generate tasks.md
    spec-next.sh / spec-brief.sh / spec-trace.sh
    spec-git.sh            # The only commit path (gates G0-G9)
    spec-reopen.sh         # Tasks affected by a spec change
    ...

  contract/                # Approval ledger contract v1 + shared fixtures (TS / Bash / Rust)
  templates/docs/          # Document templates (owned by the plugin)

  skills/                  # Spec workflow, TDD / integration procedures, framework references
  agents/                  # spec-author, spec-reviewer, impl-worker, integ-test-worker,
                           # unit-test-engineer, frontend-test-engineer, integ-test-auditor, review-worker
  rules/                   # doc-format.md (document grammar), test-taxonomy.md, verdict.md,
                           # quality-checks.md, security.md, design-principles.md, type-safety.md, ...
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
