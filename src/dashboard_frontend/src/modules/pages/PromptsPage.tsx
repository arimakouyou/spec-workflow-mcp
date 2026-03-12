import React, { useState, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useApiActions } from '../api/api';
import type { PromptSummary } from '../api/api';
import { ConfirmationModal } from '../modals/ConfirmationModal';
import { PromptEditorModal } from './PromptEditorModal';

export function PromptsPage() {
  const { t } = useTranslation();
  const { getPrompts, deletePromptOverride } = useApiActions();
  const [prompts, setPrompts] = useState<PromptSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingPrompt, setEditingPrompt] = useState<string | null>(null);
  const [resetTarget, setResetTarget] = useState<PromptSummary | null>(null);

  const loadPrompts = useCallback(async () => {
    try {
      const data = await getPrompts();
      setPrompts(data);
    } catch {
      setPrompts([]);
    } finally {
      setLoading(false);
    }
  }, [getPrompts]);

  useEffect(() => {
    loadPrompts();
  }, [loadPrompts]);

  const handleReset = useCallback(async () => {
    if (!resetTarget) return;
    try {
      await deletePromptOverride(resetTarget.name);
      setResetTarget(null);
      loadPrompts();
    } catch {
      // error handling
    }
  }, [resetTarget, deletePromptOverride, loadPrompts]);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-[var(--text-primary)]">
          {t('promptsPage.header.title', 'Prompts')}
        </h1>
        <p className="text-[var(--text-secondary)] mt-1">
          {t('promptsPage.header.subtitle', 'Customize MCP prompt templates used by AI agents')}
        </p>
      </div>

      {/* Prompt cards */}
      {loading ? (
        <div className="text-[var(--text-muted)]">{t('common.loadingContent')}</div>
      ) : prompts.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-[var(--text-muted)]">{t('promptsPage.empty', 'No prompts available')}</p>
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {prompts.map((prompt) => (
            <div
              key={prompt.name}
              className="rounded-lg border border-[var(--border-default)] bg-[var(--surface-panel)] p-4 flex flex-col"
            >
              {/* Card header */}
              <div className="flex items-start justify-between mb-2">
                <div className="flex-1 min-w-0">
                  <h3 className="text-sm font-semibold text-[var(--text-primary)] truncate">
                    {prompt.title}
                  </h3>
                  <code className="text-xs text-[var(--text-muted)]">{prompt.name}</code>
                </div>
                <span
                  className={`ml-2 flex-shrink-0 text-xs px-2 py-0.5 rounded-full font-medium ${
                    prompt.isCustomized
                      ? 'bg-[var(--interactive-primary)]/10 text-[var(--interactive-primary)]'
                      : 'bg-[var(--surface-inset)] text-[var(--text-muted)]'
                  }`}
                >
                  {prompt.isCustomized
                    ? t('promptsPage.badge.customized', 'Customized')
                    : t('promptsPage.badge.default', 'Default')}
                </span>
              </div>

              {/* Description */}
              <p className="text-xs text-[var(--text-secondary)] mb-3 line-clamp-2 flex-1">
                {prompt.description}
              </p>

              {/* Arguments */}
              {prompt.arguments && prompt.arguments.length > 0 && (
                <div className="mb-3 flex flex-wrap gap-1">
                  {prompt.arguments.map((arg) => (
                    <code
                      key={arg.name}
                      className="text-xs px-1.5 py-0.5 bg-[var(--surface-inset)] text-[var(--text-muted)] rounded"
                      title={arg.description}
                    >
                      {`{{${arg.name}}}`}{arg.required ? '*' : ''}
                    </code>
                  ))}
                </div>
              )}

              {/* Actions */}
              <div className="flex items-center gap-2 mt-auto pt-2 border-t border-[var(--border-default)]">
                <button
                  onClick={() => setEditingPrompt(prompt.name)}
                  className="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition-colors bg-[var(--interactive-primary)] text-white hover:bg-[var(--interactive-primary-hover)]"
                >
                  {t('promptsPage.actions.edit', 'Edit')}
                </button>
                {prompt.isCustomized && (
                  <button
                    onClick={() => setResetTarget(prompt)}
                    className="px-3 py-1.5 text-xs font-medium rounded-md transition-colors text-[var(--status-error)] border border-[var(--status-error)]/30 hover:bg-[var(--status-error)]/10"
                  >
                    {t('promptsPage.actions.reset', 'Reset')}
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Editor Modal */}
      <PromptEditorModal
        isOpen={editingPrompt !== null}
        onClose={() => setEditingPrompt(null)}
        promptName={editingPrompt}
        onSaved={loadPrompts}
      />

      {/* Reset Confirmation Modal */}
      <ConfirmationModal
        isOpen={resetTarget !== null}
        onClose={() => setResetTarget(null)}
        onConfirm={handleReset}
        title={t('promptsPage.resetConfirm.title', 'Reset to Default')}
        message={t('promptsPage.resetConfirm.message', 'Are you sure you want to reset this prompt to its default content? Your customizations will be lost.')}
        confirmText={t('promptsPage.resetConfirm.confirm', 'Reset')}
        variant="danger"
      />
    </div>
  );
}
