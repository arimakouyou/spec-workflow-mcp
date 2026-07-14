# Interfaces Guide

This guide describes the primary interface of Spec Workflow MCP: the Web Dashboard.

## Overview

Spec Workflow MCP provides the following interface:

- **Web Dashboard** - Browser-based visual management interface

It gives you visual and intuitive access to specifications, tasks, and approval workflows.

## Web Dashboard

### Overview

The Web Dashboard is a real-time web application that provides visual access to your specifications, tasks, and approval workflows.

### Starting the Dashboard

#### Standalone Dashboard
```bash
# Use an ephemeral port
npx -y @arimakouyou/spec-workflow-mcp@latest /path/to/project --dashboard

# Custom port
npx -y @arimakouyou/spec-workflow-mcp@latest /path/to/project --dashboard --port 3000
```

#### Alongside the MCP Server
```bash
# Run MCP server and dashboard separately (recommended)
# Terminal 1: Start the dashboard
npx -y @arimakouyou/spec-workflow-mcp@latest --dashboard

# Terminal 2: Start the MCP server
npx -y @arimakouyou/spec-workflow-mcp@latest /path/to/project
```

### Dashboard Features

#### Main View

The dashboard home displays:

- **Project Summary**
  - Number of active specifications
  - Total tasks
  - Completion percentage
  - Recent activity

- **Spec Cards**
  - Spec name and status
  - Progress bar
  - Document indicators
  - Quick actions

#### Spec Detail View

Clicking a specification displays:

- **Document Tabs**
  - Requirements
  - Design
  - Tasks

- **Document Content**
  - Rendered Markdown
  - Syntax highlighting
  - Table of contents

- **Approval Actions**
  - Approve button
  - Request Changes
  - Reject options
  - Comments field

#### Task Management

The task view provides:

- **Hierarchical Task List**
  - Numbered tasks (1.0, 1.1, 1.1.1)
  - Status indicators
  - Progress tracking

- **Task Actions**
  - Copy prompt button
  - Mark as completed
  - Add notes
  - View dependencies

- **Progress Visualization**
  - Overall progress bar
  - Section progress
  - Time estimations

#### Steering Documents

Access project guidance:

- **Product Steering**
  - Vision and goals
  - User personas
  - Success metrics

- **Technical Steering**
  - Architectural decisions
  - Technology choices
  - Performance targets

- **Structural Steering**
  - File organization
  - Naming conventions
  - Module boundaries

### Dashboard Navigation

#### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Alt + S` | Focus specifications list |
| `Alt + T` | Show tasks |
| `Alt + R` | Show requirements |
| `Alt + D` | Show design |
| `Alt + A` | Open approval dialog |
| `Esc` | Close dialog |

#### URL Structure

Direct links to specific views:
- `/` - Home dashboard
- `/spec/{name}` - Specific specification
- `/spec/{name}/requirements` - Requirements document
- `/spec/{name}/design` - Design document
- `/spec/{name}/tasks` - Task list
- `/steering/{type}` - Steering document

### Real-Time Updates

The dashboard uses WebSockets for live updates:

- **Auto Refresh**
  - New specifications appear immediately
  - Task status updates
  - Progress changes
  - Approval notifications

- **Connection Status**
  - Green: Connected
  - Yellow: Reconnecting
  - Red: Disconnected

- **Notification System**
  - Approval requests
  - Task completion
  - Error alerts
  - Success messages

### Dashboard Customization

#### Theme Settings

Toggle between light and dark modes:
- Click the theme icon in the header
- Persists across sessions
- Respects system preference

#### Language Selection

Change the interface language:
1. Click the settings icon
2. Choose language from the dropdown
3. Interface updates immediately

Supported languages:
- English (en)
- Japanese (ja)
- Chinese (zh)
- Spanish (es)
- Portuguese (pt)
- German (de)
- French (fr)
- Russian (ru)
- Italian (it)
- Korean (ko)
- Arabic (ar)

#### Display Options

Customize view preferences:
- Compact/expanded spec cards
- Show/hide completed tasks
- Document font size
- Code syntax theme

## Mobile and Tablet Access

### Web Dashboard on Mobile

The dashboard is responsive:

- **Phone View**
  - Stacked spec cards
  - Collapsible navigation
  - Touch-optimized buttons
  - Swipe gestures

- **Tablet View**
  - Parallel layouts
  - Touch interactions
  - Optimized spacing
  - Landscape support

### Limitations on Mobile

- Limited keyboard shortcuts
- Restricted multitasking
- Simplified interactions

## Accessibility Features

### Web Dashboard

- **Keyboard Navigation**
  - Tab through interactive elements
  - Enter to activate
  - Escape to cancel
  - Arrow keys for lists

- **Screen Reader Support**
  - ARIA labels
  - Role attributes
  - Status announcements
  - Focus management

- **Visual Accessibility**
  - High contrast mode
  - Adjustable font sizes
  - Colorblind-friendly palettes
  - Focus indicators

## Performance Optimization

### Dashboard Performance

- **Lazy Loading**
  - Load documents on-demand
  - Pagination for long lists
  - Progressive rendering
  - Image optimization

- **Caching Strategies**
  - Browser caching
  - Service Workers
  - Limited offline support
  - Rapid navigation

## Troubleshooting Interface Issues

### Dashboard Issues

| Issue | Solution |
|-------|----------|
| Doesn't load | Confirm server is running, verify URL |
| No updates | Check WebSocket connection, refresh page |
| Approvals fail | Ensure dashboard and MCP server are connected |
| Broken styles | Clear browser cache, check console |

## Advanced Usage

### Custom Dashboard URL

Set up across multiple terminals:
```bash
# Terminal 1: MCP Server
npx -y @arimakouyou/spec-workflow-mcp@latest /project

# Terminal 2: Dashboard
npx -y @arimakouyou/spec-workflow-mcp@latest /project --dashboard --port 3000
```

## Related Documents

- [Configuration Guide](CONFIGURATION.md) - Setup and settings
- [User Guide](USER-GUIDE.md) - Using the interface
- [Workflow Process](WORKFLOW.md) - Development workflow
- [Troubleshooting](TROUBLESHOOTING.md) - General issues