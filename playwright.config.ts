import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  testIgnore: '**/worktree-no-shared.spec.ts',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://127.0.0.1:5173',
    trace: 'on-first-retry',
    screenshot: 'on',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: [
    {
      command: 'npm run dev -- --dashboard --no-open --port 5000',
      url: 'http://127.0.0.1:5000/api/test',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
      env: {
        SPEC_WORKFLOW_RATE_LIMIT_ENABLED: 'false'
      }
    },
    {
      command: 'npm run dev:dashboard -- --host 127.0.0.1 --port 5173',
      url: 'http://127.0.0.1:5173',
      reuseExistingServer: !process.env.CI,
      timeout: 120000,
    }
  ],
});
