# Internationalization (i18n) Structure

## Overview

The spec-workflow-mcp project implements internationalization across three distinct components, each with its own translation file structure to meet specific UI and functional requirements.

## Supported Languages

The project supports 11 languages:
- English (en) 🇺🇸
- Japanese (ja) 🇯🇵
- Chinese (zh) 🇨🇳
- Spanish (es) 🇪🇸
- Portuguese (pt) 🇧🇷
- German (de) 🇩🇪
- French (fr) 🇫🇷
- Russian (ru) 🇷🇺
- Italian (it) 🇮🇹
- Korean (ko) 🇰🇷
- Arabic (ar) 🇸🇦

## Translation File Locations

### 1. Backend MCP Server (`src/locales/`)
- **Purpose**: Translations for MCP tool responses and server messages
- **Structure**: Starts with keys like `tools`, `specStatus`, `errors`
- **Usage**: Used by the MCP server when responding to tool calls
- **Example keys**:
  ```json
  {
    "tools": {
      "steeringGuide": { ... },
      "specStatus": { ... }
    }
  }
  ```


### 3. Dashboard Frontend (`src/dashboard_frontend/src/locales/`)
- **Purpose**: Translations for the web dashboard UI
- **Structure**: Sections for dashboard widgets, settings, navigation
- **Usage**: Used in the standalone web dashboard
- **Example keys**:
  ```json
  {
    "nav": { ... },
    "dashboard": { ... },
    "settings": { ... }
  }
  ```

Each component serves a different purpose and has unique translation needs:

1. **Backend MCP Server**: Focuses on tool descriptions, error messages, and workflow guidance
2. **Dashboard Frontend**: Offers a comprehensive web-based project dashboard

The different structures are **intentional and correct** - they are tailored translation sets for each component's specific requirements.

## Validation

All translation files are validated during the build process:

```bash
npm run validate:i18n
```

This script checks:
- JSON syntax validity
- Mustache template variable consistency across languages
- File presence for all supported languages

## Adding New Languages

To add a new language:

1. Add the language code to `SUPPORTED_LANGUAGES` in:
   - `src/core/i18n.ts`
   - `scripts/validate-i18n.js`

2. Create translation files in both locations:
   - `src/locales/{lang}.json`
   - `src/dashboard_frontend/src/locales/{lang}.json`

3. Update language selector:
   - Dashboard: `src/dashboard_frontend/src/components/LanguageSelector.tsx`

4. Import and register translations in i18n configuration:
   - `src/dashboard_frontend/src/i18n.ts`

## Bundle Size Considerations

With 11 languages, bundle size impact should be monitored. For production deployments with large user bases, consider:

- Implementing lazy loading of language packs
- Setting `REACT_APP_I18N_DYNAMIC=true` for dynamic imports
- Loading only the user's selected language initially

Current implementation uses eager loading for better user experience during language switching.

## Recent Issues & Fixes

### Version 0.0.30 - Critical Translation Fix

A critical issue was resolved where multiple components were using translation functions (`t()`) without properly declaring the `useTranslation` hook, causing "ReferenceError: t is not defined" errors. This affected:

- Task management dropdown functionality
- Comment modal interfaces  
- Volume controls
- Alert dialogs

**Solution**: All affected components now properly import and declare the `useTranslation` hook, and missing translation keys have been added across all 11 languages.

**Prevention**: Enhanced documentation includes component templates and validation checklists to prevent similar issues.

For detailed troubleshooting information, see the [i18n Guide](./i18n-guide.md#critical-issue-referenceerror-t-is-not-defined).