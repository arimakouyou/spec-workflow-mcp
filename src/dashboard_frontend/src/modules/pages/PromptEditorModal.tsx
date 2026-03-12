import React, { useState, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import { useApiActions } from '../api/api';
import type { PromptDetail } from '../api/api';

interface PromptEditorModalProps {
  isOpen: boolean;
  onClose: () => void;
  promptName: string | null;
  onSaved: () => void;
}

export function PromptEditorModal({ isOpen, onClose, promptName, onSaved }: PromptEditorModalProps) {
  const { t } = useTranslation();
  const { getPrompt, savePromptOverride } = useApiActions();
  const [prompt, setPrompt] = useState<PromptDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [customContent, setCustomContent] = useState('');
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);

  useEffect(() => {
    if (!isOpen || !promptName) {
      setPrompt(null);
      setCustomContent('');
      setHasChanges(false);
      return;
    }

    let active = true;
    setLoading(true);

    getPrompt(promptName)
      .then((data) => {
        if (active) {
          setPrompt(data);
          setCustomContent(data.customContent || data.defaultContent || '');
          setHasChanges(false);
        }
      })
      .catch(() => {
        if (active) setPrompt(null);
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => { active = false; };
  }, [isOpen, promptName, getPrompt]);

  const handleSave = useCallback(async () => {
    if (!promptName || !customContent.trim()) return;
    setSaving(true);
    try {
      const result = await savePromptOverride(promptName, customContent);
      if (result.ok) {
        setHasChanges(false);
        onSaved();
        onClose();
      }
    } finally {
      setSaving(false);
    }
  }, [promptName, customContent, savePromptOverride, onSaved, onClose]);

  const handleContentChange = useCallback((value: string) => {
    setCustomContent(value);
    setHasChanges(true);
  }, []);

  // Handle keyboard shortcuts
  useEffect(() => {
    if (!isOpen) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        if (hasChanges && !saving) handleSave();
      }
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose, hasChanges, saving, handleSave]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50" />
      <div
        className="relative bg-[var(--surface-panel)] rounded-lg shadow-[var(--shadow-overlay)] w-[95vw] max-w-6xl h-[85vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[var(--border-default)]">
          <div>
            <h2 className="text-lg font-semibold text-[var(--text-primary)]">
              {t('promptsPage.editor.title', 'Edit Prompt')}
            </h2>
            {prompt && (
              <p className="text-sm text-[var(--text-muted)] mt-0.5">
                {prompt.title} — {prompt.name}
              </p>
            )}
          </div>
          <div className="flex items-center gap-3">
            {hasChanges && (
              <span className="text-xs text-[var(--status-warning)]">
                {t('editor.markdown.unsavedChanges', 'Unsaved changes')}
              </span>
            )}
            <button
              onClick={onClose}
              className="p-2 rounded-md text-[var(--text-muted)] hover:bg-[var(--surface-hover)] transition-colors"
              aria-label={t('common.closeModalAria')}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        {/* Body */}
        {loading ? (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-[var(--text-muted)]">{t('common.loadingContent')}</p>
          </div>
        ) : prompt ? (
          <div className="flex-1 flex flex-col lg:flex-row overflow-hidden">
            {/* Left: Default content (read-only) */}
            <div className="flex-1 flex flex-col border-b lg:border-b-0 lg:border-r border-[var(--border-default)] min-h-0">
              <div className="px-4 py-2 border-b border-[var(--border-default)] bg-[var(--surface-inset)]">
                <span className="text-xs font-medium text-[var(--text-secondary)]">
                  {t('promptsPage.editor.defaultContent', 'Default Content')}
                  <span className="ml-2 text-[var(--text-muted)]">({t('promptsPage.editor.readOnly', 'read-only')})</span>
                </span>
              </div>
              <pre className="flex-1 overflow-auto p-4 text-sm text-[var(--text-secondary)] whitespace-pre-wrap font-mono leading-relaxed">
                {prompt.defaultContent}
              </pre>
            </div>

            {/* Right: Custom content (editable) */}
            <div className="flex-1 flex flex-col min-h-0">
              <div className="px-4 py-2 border-b border-[var(--border-default)] bg-[var(--surface-inset)]">
                <span className="text-xs font-medium text-[var(--text-secondary)]">
                  {t('promptsPage.editor.customContent', 'Custom Content')}
                </span>
              </div>
              <textarea
                className="flex-1 w-full p-4 text-sm bg-transparent text-[var(--text-primary)] font-mono leading-relaxed resize-none focus:outline-none"
                value={customContent}
                onChange={(e) => handleContentChange(e.target.value)}
                placeholder={t('promptsPage.editor.placeholder', 'Enter your custom prompt content...')}
                spellCheck={false}
              />
            </div>
          </div>
        ) : (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-[var(--text-muted)]">{t('promptsPage.editor.notFound', 'Prompt not found')}</p>
          </div>
        )}

        {/* Footer */}
        {prompt && (
          <div className="px-6 py-3 border-t border-[var(--border-default)] flex items-center justify-between">
            {/* Available variables */}
            <div className="flex flex-wrap gap-1.5 items-center">
              <span className="text-xs text-[var(--text-muted)] mr-1">
                {t('promptsPage.editor.variables', 'Variables:')}
              </span>
              <code className="text-xs px-1.5 py-0.5 bg-[var(--surface-inset)] text-[var(--text-secondary)] rounded">
                {'{{projectPath}}'}
              </code>
              <code className="text-xs px-1.5 py-0.5 bg-[var(--surface-inset)] text-[var(--text-secondary)] rounded">
                {'{{dashboardUrl}}'}
              </code>
              {prompt.arguments?.map((arg) => (
                <code key={arg.name} className="text-xs px-1.5 py-0.5 bg-[var(--surface-inset)] text-[var(--text-secondary)] rounded">
                  {`{{${arg.name}}}`}
                </code>
              ))}
            </div>

            {/* Action buttons */}
            <div className="flex items-center gap-2">
              <button
                onClick={onClose}
                className="btn-secondary px-4 py-1.5 text-sm"
              >
                {t('common.cancel')}
              </button>
              <button
                onClick={handleSave}
                disabled={!hasChanges || saving}
                className="px-4 py-1.5 text-sm rounded-md font-medium transition-colors bg-[var(--interactive-primary)] text-white hover:bg-[var(--interactive-primary-hover)] disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {saving ? t('editor.markdown.saving') : t('editor.markdown.save')}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
