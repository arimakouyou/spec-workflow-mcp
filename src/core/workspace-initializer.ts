import { promises as fs } from 'fs';
import { join } from 'path';
import { PathUtils } from './path-utils.js';
import { ImplementationLogMigrator } from './implementation-log-migrator.js';
import { getGlobalDir } from './global-dir.js';

export class WorkspaceInitializer {
  private projectPath: string;
  private version: string;

  constructor(projectPath: string, version: string) {
    this.projectPath = projectPath;
    this.version = version;
  }

  async initializeWorkspace(): Promise<void> {
    // Create all necessary directories
    await this.initializeDirectories();

    // Migrate implementation logs from JSON to Markdown format
    await this.migrateImplementationLogs();
  }

  // 文書テンプレートはプラグイン(.claude-plugin/templates/docs/)が所有するため、
  // サーバーはテンプレートの配置も user-templates の上書きも行わない。
  private async initializeDirectories(): Promise<void> {
    const workflowRoot = PathUtils.getWorkflowRoot(this.projectPath);

    const directories = [
      'approvals',
      'archive',
      'specs',
      'steering',
      'steering/logs',
      'user-prompts'
    ];

    for (const dir of directories) {
      const dirPath = join(workflowRoot, dir);
      await fs.mkdir(dirPath, { recursive: true });
    }
  }

  /**
   * Migrate implementation logs from JSON to Markdown format
   * Runs on server startup to handle automatic migration for existing specs
   */
  private async migrateImplementationLogs(): Promise<void> {
    try {
      const userDataDir = getGlobalDir();
      const specsDir = join(PathUtils.getWorkflowRoot(this.projectPath), 'specs');

      // Create user data directory if it doesn't exist
      await fs.mkdir(userDataDir, { recursive: true });

      const migrator = new ImplementationLogMigrator(userDataDir);
      await migrator.migrateAllSpecs(specsDir);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(`Implementation log migration failed: ${errorMessage}`);
      // Don't throw - migration failure shouldn't break server startup
    }
  }
}
