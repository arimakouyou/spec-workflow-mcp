/**
 * Unified Task Parser Module
 * Provides consistent task parsing across all components
 */

/**
 * Parse a prompt string into structured sections if it contains pipe separators
 * @param promptText The raw prompt text
 * @returns Array of prompt sections or undefined if not structured
 */
function parseStructuredPrompt(promptText: string): PromptSection[] | undefined {
  // Validate input
  if (!promptText || typeof promptText !== 'string') {
    return undefined;
  }
  
  // Check if the prompt contains pipe separators (indicating structured format)
  if (!promptText.includes('|')) {
    return undefined;
  }

  const sections: PromptSection[] = [];
  
  // Split by pipe and process each section
  const parts = promptText.split('|').map(part => part.trim()).filter(part => part.length > 0);
  
  // Return early if no valid parts after filtering
  if (parts.length === 0) {
    return undefined;
  }
  
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    // Part is guaranteed to be non-empty due to filter above
    
    // Special handling for the first part - it might contain preamble text before the first key
    if (i === 0) {
      // Look for the last occurrence of a known key pattern in the first part
      const knownKeys = ['Role', 'Task', 'Context', 'Instructions', 'Requirements', 'Leverage', 'Success', 'Restrictions'];
      let lastKeyIndex = -1;
      
      for (const key of knownKeys) {
        const keyPattern = new RegExp(`\\b${key}:`, 'i');
        const match = part.match(keyPattern);
        if (match && match.index !== undefined && match.index > lastKeyIndex) {
          lastKeyIndex = match.index;
        }
      }
      
      if (lastKeyIndex > -1 && lastKeyIndex < part.length) {
        // Extract the key-value pair starting from the found key
        const keyValuePart = part.substring(lastKeyIndex);
        const colonIndex = keyValuePart.indexOf(':');
        if (colonIndex > 0 && colonIndex < keyValuePart.length - 1) {
          const key = keyValuePart.substring(0, colonIndex).trim();
          const value = keyValuePart.substring(colonIndex + 1).trim();
          
          // Validate key and value are non-empty after cleaning
          if (key && value) {
            const cleanKey = key.replace(/^_+|_+$/g, '');
            const cleanValue = value.replace(/^_+|_+$/g, '');
            
            // Only add if both cleaned values are non-empty
            if (cleanKey && cleanValue) {
              sections.push({ key: cleanKey, value: cleanValue });
            }
          }
        }
      }
      continue;
    }
    
    // For other parts, look for "Key: Value" pattern
    const colonIndex = part.indexOf(':');
    if (colonIndex > 0 && colonIndex < part.length - 1) {
      const key = part.substring(0, colonIndex).trim();
      const value = part.substring(colonIndex + 1).trim();
      
      // Validate key and value exist
      if (key && value) {
        // Clean up any markdown formatting (underscores for italics, etc.)
        const cleanKey = key.replace(/^_+|_+$/g, '');
        const cleanValue = value.replace(/^_+|_+$/g, '');
        
        // Only add if both cleaned values are non-empty
        if (cleanKey && cleanValue) {
          sections.push({ key: cleanKey, value: cleanValue });
        }
      }
    } else if (colonIndex <= 0 || colonIndex >= part.length - 1) {
      // If no valid colon position, treat as continuation only if previous section exists
      if (sections.length > 0) {
        const cleanedPart = part.replace(/^_+|_+$/g, '').trim();
        if (cleanedPart) {
          sections[sections.length - 1].value += ' | ' + cleanedPart;
        }
      }
    }
  }
  
  return sections.length > 0 ? sections : undefined;
}
export interface PromptSection {
  key: string;                         // Section name (e.g., "Role", "Task", "Restrictions")
  value: string;                       // Section content
}

export interface ParsedTask {
  id: string;                          // Task ID (e.g., "1", "1.1", "2.3")
  description: string;                 // Task description
  status: 'pending' | 'in-progress' | 'completed';
  lineNumber: number;                  // Line number in the file (0-based)
  indentLevel: number;                 // Indentation level (for hierarchy)
  isHeader: boolean;                   // Whether this is a header task (no implementation details)

  // Optional metadata
  requirements?: string[];              // Referenced requirements
  leverage?: string;                   // Code to leverage
  files?: string[];                    // Files to modify/create
  purposes?: string[];                 // Purpose statements
  implementationDetails?: string[];    // Implementation bullet points
  prompt?: string;                     // AI prompt for this task (full text)
  promptStructured?: PromptSection[];  // Structured prompt sections (if prompt contains pipe separators)
  testFocus?: string;                  // RED phase test guidance
  isPhaseReview?: boolean;             // Whether this is a phase review task
  phase?: string;                      // Owning phase name (e.g., "Phase 1: Core Domain Layer")
  dependsOn?: string[];               // 依存先タスクID（例: ["1.1", "1.2"]）

  // For backward compatibility
  completed: boolean;                  // true if status === 'completed'
  inProgress: boolean;                 // true if status === 'in-progress'
}
export interface PhaseInfo {
  name: string;           // e.g., "Phase 1: Core Domain Layer"
  taskIds: string[];      // Task IDs belonging to this phase
  reviewTaskId?: string;  // ID of the phase review task (if any)
}

export interface TaskParserResult {
  tasks: ParsedTask[];
  inProgressTask: string | null;       // ID of current in-progress task (e.g., "1.1")
  phases: PhaseInfo[];                 // Phase groupings (empty if no phases)
  summary: {
    total: number;
    completed: number;
    inProgress: number;
    pending: number;
    headers: number;
  };
}

/**
 * Parse tasks from markdown content
 * Handles any checkbox format at any indentation level
 */
export function parseTasksFromMarkdown(content: string): TaskParserResult {
  const lines = content.split('\n');
  const tasks: ParsedTask[] = [];
  let inProgressTask: string | null = null;

  // Track phases from ## Phase headings
  const phases: PhaseInfo[] = [];
  let currentPhase: string | undefined;
  const phaseHeadingLines: { line: number; name: string }[] = [];

  for (let i = 0; i < lines.length; i++) {
    const phaseMatch = lines[i].match(/^##\s+(Phase\s+\d+\s*:.+)/i);
    if (phaseMatch) {
      const phaseName = phaseMatch[1].trim();
      phaseHeadingLines.push({ line: i, name: phaseName });
      phases.push({ name: phaseName, taskIds: [] });
    }
  }

  // Find all lines with checkboxes (supports both - and * list markers)
  const checkboxIndices: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].match(/^\s*[-*]\s+\[([ x\-])\]/)) {
      checkboxIndices.push(i);
    }
  }
  
  // Process each checkbox task
  for (let idx = 0; idx < checkboxIndices.length; idx++) {
    const lineNumber = checkboxIndices[idx];
    const endLine = idx < checkboxIndices.length - 1 ? checkboxIndices[idx + 1] : lines.length;
    
    const line = lines[lineNumber];
    const checkboxMatch = line.match(/^(\s*)([-*])\s+\[([ x\-])\]\s+(.+)/);
    
    if (!checkboxMatch) continue;

    const indent = checkboxMatch[1];
    const listMarker = checkboxMatch[2]; // '-' or '*'
    const statusChar = checkboxMatch[3];
    const taskText = checkboxMatch[4];
    
    // Determine status
    let status: 'pending' | 'in-progress' | 'completed';
    if (statusChar === 'x') {
      status = 'completed';
    } else if (statusChar === '-') {
      status = 'in-progress';
    } else {
      status = 'pending';
    }
    
    // Extract task ID and description
    // Match patterns like "1. Description", "1.1 Description", "2.1. Description" etc
    // Also handles escaped periods from MDXEditor: "1\. Description"
    const taskMatch = taskText.match(/^(\d+(?:\.\d+)*)\s*\\?\.?\s+(.+)/);
    
    let taskId: string;
    let description: string;
    
    if (taskMatch) {
      taskId = taskMatch[1];
      description = taskMatch[2];
    } else {
      // No task number found, skip this task
      continue;
    }
    
    // Parse metadata from content between this task and the next
    const requirements: string[] = [];
    const leverage: string[] = [];
    const files: string[] = [];
    const purposes: string[] = [];
    const implementationDetails: string[] = [];
    const dependsOn: string[] = [];
    let prompt: string | undefined;
    let testFocus: string | undefined;
    let isPhaseReview = false;

    for (let lineIdx = lineNumber + 1; lineIdx < endLine; lineIdx++) {
      const contentLine = lines[lineIdx].trim();
      
      // Skip empty lines
      if (!contentLine) continue;
      // Check for metadata patterns
      // IMPORTANT: Check for _Prompt: first since it can contain nested _Requirements: and _Leverage:
      if (contentLine.includes('_Prompt:')) {
        // Capture everything after _Prompt: until the final closing underscore
        const promptMatch = contentLine.match(/_Prompt:\s*(.+)_$/);
        if (promptMatch) {
          prompt = promptMatch[1].trim();
        } else {
          // If no closing underscore on same line, capture multi-line
          const afterPrompt = contentLine.match(/_Prompt:\s*(.+)$/);
          let promptText = afterPrompt ? afterPrompt[1] : '';
          promptText = promptText.replace(/_$/, '').trim();

          // Accumulate continuation lines that are not new bullets/metadata
          let j = lineIdx + 1;
          while (j < endLine) {
            const nextTrim = lines[j].trim();
            if (!nextTrim) break; // stop at blank line
            // Stop if we hit another bullet/metadata marker or files/purpose sections
            if (
              /^[-*]\s/.test(nextTrim) ||
              /^Files?:/i.test(nextTrim) ||
              /^Purpose:/i.test(nextTrim)
            ) {
              break;
            }
            promptText += ' ' + nextTrim.replace(/_$/, '').trim();
            j++;
          }
          prompt = promptText;
          // Skip consumed continuation lines
          lineIdx = j - 1;
        }
      } else if (contentLine.includes('_Requirements:') && !contentLine.includes('_Prompt:')) {
        // Only process if not inside a prompt
        const reqMatch = contentLine.match(/_Requirements:\s*([^_]+?)_/);
        if (reqMatch) {
          const reqText = reqMatch[1].trim();
          // Split by comma and filter out empty/NFR
          requirements.push(...reqText.split(',').map(r => r.trim()).filter(r => r && r !== 'NFR'));
        }
      } else if (contentLine.includes('_Leverage:') && !contentLine.includes('_Prompt:')) {
        // Only process if not inside a prompt
        const levMatch = contentLine.match(/_Leverage:\s*([^_]+?)_/);
        if (levMatch) {
          const levText = levMatch[1].trim();
          leverage.push(...levText.split(',').map(l => l.trim()).filter(l => l));
        }
      } else if (contentLine.includes('_TestFocus:') && !contentLine.includes('_Prompt:')) {
        const tfMatch = contentLine.match(/_TestFocus:\s*([^_]+?)_/);
        if (tfMatch) {
          testFocus = tfMatch[1].trim();
        }
      } else if (contentLine.includes('_PhaseReview:') && !contentLine.includes('_Prompt:')) {
        const prMatch = contentLine.match(/_PhaseReview:\s*([^_]+?)_/);
        if (prMatch) {
          isPhaseReview = prMatch[1].trim().toLowerCase() === 'true';
        }
      } else if (contentLine.includes('_DependsOn:') && !contentLine.includes('_Prompt:')) {
        const depMatch = contentLine.match(/_DependsOn:\s*([^_]+?)_/);
        if (depMatch) {
          dependsOn.push(...depMatch[1].split(',').map(d => d.trim()).filter(d => d));
        }
      } else if (contentLine.match(/Files?:/)) {
        const fileMatch = contentLine.match(/Files?:\s*(.+)$/);
        if (fileMatch) {
          // Split by comma and clean up each file path
          const filePaths = fileMatch[1]
            .split(',')
            .map(f => f.trim().replace(/\(.*?\)/, '').trim())
            .filter(f => f.length > 0);
          files.push(...filePaths);
        }
      } else if (contentLine.match(/^[-*]\s/) && !contentLine.match(/^[-*]\s+\[/)) {
        // Regular bullet point - could be implementation detail or purpose
        const bulletContent = contentLine.replace(/^[-*]\s+/, '').trim();
        if (bulletContent.startsWith('Purpose:')) {
          purposes.push(bulletContent.substring(8).trim());
        } else if (!bulletContent.match(/^Files?:/) && !bulletContent.match(/^Purpose:/)) {
          implementationDetails.push(bulletContent);
        }
      }
    }
    
    // Determine if this is a header task (has no implementation details)
    const hasDetails = requirements.length > 0 ||
                      leverage.length > 0 ||
                      files.length > 0 ||
                      purposes.length > 0 ||
                      implementationDetails.length > 0 ||
                      !!prompt ||
                      isPhaseReview;

    // Parse structured prompt if applicable
    let promptStructured: PromptSection[] | undefined;
    if (prompt) {
      promptStructured = parseStructuredPrompt(prompt);
    }

    // Determine which phase this task belongs to
    let taskPhase: string | undefined;
    if (phaseHeadingLines.length > 0) {
      for (let p = phaseHeadingLines.length - 1; p >= 0; p--) {
        if (lineNumber > phaseHeadingLines[p].line) {
          taskPhase = phaseHeadingLines[p].name;
          break;
        }
      }
    }

    const task: ParsedTask = {
      id: taskId,
      description,
      status,
      lineNumber,
      indentLevel: indent.length / 2, // Assuming 2 spaces per indent level
      isHeader: !hasDetails,
      completed: status === 'completed',
      inProgress: status === 'in-progress',

      // Add metadata if present
      ...(requirements.length > 0 && { requirements }),
      ...(leverage.length > 0 && { leverage: leverage.join(', ') }),
      ...(files.length > 0 && { files }),
      ...(purposes.length > 0 && { purposes }),
      ...(implementationDetails.length > 0 && { implementationDetails }),
      ...(prompt && { prompt }),
      ...(promptStructured && { promptStructured }),
      ...(testFocus && { testFocus }),
      ...(isPhaseReview && { isPhaseReview }),
      ...(taskPhase && { phase: taskPhase }),
      ...(dependsOn.length > 0 && { dependsOn })
    };
    tasks.push(task);

    // Register task in its phase
    if (taskPhase) {
      const phaseInfo = phases.find(p => p.name === taskPhase);
      if (phaseInfo) {
        phaseInfo.taskIds.push(taskId);
        if (isPhaseReview) {
          phaseInfo.reviewTaskId = taskId;
        }
      }
    }
    
    // Track first in-progress task (for UI highlighting)
    if (status === 'in-progress' && !inProgressTask) {
      inProgressTask = taskId;  // Just store the task ID for UI comparison
    }
  }
  
  // Calculate summary
  const summary = {
    total: tasks.length,
    completed: tasks.filter(t => t.status === 'completed').length,
    inProgress: tasks.filter(t => t.status === 'in-progress').length,
    pending: tasks.filter(t => t.status === 'pending').length,
    headers: tasks.filter(t => t.isHeader).length
  };
  
  return {
    tasks,
    inProgressTask,
    phases,
    summary
  };
}

/**
 * Update task status in markdown content
 * Handles any indentation level and task numbering format
 */
export function updateTaskStatus(
  content: string, 
  taskId: string, 
  newStatus: 'pending' | 'in-progress' | 'completed'
): string {
  const lines = content.split('\n');
  const statusMarker = newStatus === 'completed' ? 'x' : 
                       newStatus === 'in-progress' ? '-' : 
                       ' ';
  
  // Find and update the task line
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Match checkbox line with task ID in the description (supports both - and * list markers)
    // Pattern: - [x] 1.1 Task description  or  * [x] 1.1 Task description
    const checkboxMatch = line.match(/^(\s*)([-*])\s+\[([ x\-])\]\s+(.+)/);

    if (checkboxMatch) {
      const prefix = checkboxMatch[1];
      const listMarker = checkboxMatch[2]; // Preserve original list marker
      const taskText = checkboxMatch[4];

      // Check if this line contains our target task ID
      // Match patterns like "1. Description", "1.1 Description", "2.1. Description" etc
      // Also handles escaped periods from MDXEditor: "1\. Description"
      const taskMatch = taskText.match(/^(\d+(?:\.\d+)*)\s*\\?\.?\s+(.+)/);

      if (taskMatch && taskMatch[1] === taskId) {
        // Reconstruct the line with new status, preserving the original list marker
        const statusPart = `${listMarker} [${statusMarker}] `;
        lines[i] = prefix + statusPart + taskText;
        return lines.join('\n');
      }
    }
  }
  
  // Task not found
  return content;
}

/**
 * Find the next pending task that is not a header
 */
export function findNextPendingTask(tasks: ParsedTask[]): ParsedTask | null {
  return tasks.find(t => t.status === 'pending' && !t.isHeader) || null;
}

/**
 * Get task by ID
 */
export function getTaskById(tasks: ParsedTask[], taskId: string): ParsedTask | undefined {
  return tasks.find(t => t.id === taskId);
}

/**
 * Export for backward compatibility with existing code
 */
export function parseTaskProgress(content: string): {
  total: number;
  completed: number;
  pending: number;
} {
  const result = parseTasksFromMarkdown(content);
  return {
    total: result.summary.total,
    completed: result.summary.completed,
    pending: result.summary.pending
  };
}

// --- Wave-based parallel execution ---

export interface ExecutionWave {
  waveIndex: number;
  taskIds: string[];
}

/**
 * Phase内のタスクから依存関係に基づく実行Waveを計算する
 * トポロジカルソートにより、依存関係のないタスクを同一Waveにグループ化
 */
export function computeExecutionWaves(
  tasks: ParsedTask[],
  phase: PhaseInfo
): ExecutionWave[] {
  // Phase内の実行可能タスク（ヘッダーとPhaseReview除く）
  const phaseTasks = tasks.filter(t =>
    phase.taskIds.includes(t.id) && !t.isHeader && !t.isPhaseReview
  );

  if (phaseTasks.length === 0) {
    // PhaseReviewのみの場合
    if (phase.reviewTaskId) {
      return [{ waveIndex: 0, taskIds: [phase.reviewTaskId] }];
    }
    return [];
  }

  // 依存マップ構築
  const deps = new Map<string, string[]>();
  for (const task of phaseTasks) {
    deps.set(task.id, task.dependsOn || []);
  }

  const completed = new Set<string>();
  // 既に完了したタスクを初期セットに追加（途中再開対応）
  for (const task of phaseTasks) {
    if (task.status === 'completed') {
      completed.add(task.id);
    }
  }

  const waves: ExecutionWave[] = [];
  let remaining = phaseTasks.filter(t => t.status !== 'completed');
  let waveIndex = 0;

  while (remaining.length > 0) {
    // 全依存が completed に含まれるタスクを抽出
    const ready = remaining.filter(t => {
      const taskDeps = deps.get(t.id) || [];
      return taskDeps.every(d => completed.has(d));
    });

    if (ready.length === 0) {
      // 循環依存により進行不可（バリデーションで事前検出すべき）
      break;
    }

    waves.push({ waveIndex, taskIds: ready.map(t => t.id) });
    ready.forEach(t => completed.add(t.id));
    remaining = remaining.filter(t => !completed.has(t.id));
    waveIndex++;
  }

  // PhaseReview は常に最終 Wave
  if (phase.reviewTaskId) {
    waves.push({ waveIndex, taskIds: [phase.reviewTaskId] });
  }

  return waves;
}

/**
 * 次に実行可能な Wave を返す
 * 各 Phase を順に走査し、pending タスクを含む最初の Wave を返す
 */
export function findNextPendingWave(
  tasks: ParsedTask[],
  phases: PhaseInfo[]
): { phase: PhaseInfo; wave: ExecutionWave } | null {
  for (const phase of phases) {
    const waves = computeExecutionWaves(tasks, phase);
    for (const wave of waves) {
      const pendingInWave = wave.taskIds.filter(id => {
        const task = tasks.find(t => t.id === id);
        return task && task.status === 'pending';
      });
      if (pendingInWave.length > 0) {
        return {
          phase,
          wave: { ...wave, taskIds: pendingInWave }
        };
      }
    }
  }
  return null;
}
