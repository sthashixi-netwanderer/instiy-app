import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { FileText, Shield, Save, Loader, Eye, Edit3 } from 'lucide-react';
import { useAlert } from '../components/use-alert';

interface Policy {
  id: string;
  policy_type: string;
  title: string;
  content: string;
  is_active: boolean;
  updated_at: string;
}

export const Policies: React.FC = () => {
  const [policies, setPolicies] = useState<Policy[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'privacy_policy' | 'terms_conditions'>('privacy_policy');
  const [content, setContent] = useState('');
  const [title, setTitle] = useState('');
  const [isActive, setIsActive] = useState(true);
  const [saving, setSaving] = useState(false);
  const [previewMode, setPreviewMode] = useState(false);
  const [saved, setSaved] = useState(false);
  const { showAlert, AlertComponent } = useAlert();

  const fetchPolicies = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('policies')
        .select('*')
        .order('policy_type');
      if (error) throw error;
      setPolicies(data || []);
    } catch (error) {
      console.error('Error fetching policies:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchPolicies(); }, []);

  useEffect(() => {
    const policy = policies.find(p => p.policy_type === activeTab);
    if (policy) {
      setContent(policy.content);
      setTitle(policy.title);
      setIsActive(policy.is_active);
    } else {
      setContent('');
      setTitle(activeTab === 'privacy_policy' ? 'Privacy Policy' : 'Terms & Conditions');
      setIsActive(true);
    }
    setPreviewMode(false);
    setSaved(false);
  }, [activeTab, policies]);

  const handleSave = async () => {
    setSaving(true);
    setSaved(false);
    try {
      const existing = policies.find(p => p.policy_type === activeTab);
      if (existing) {
        const { error } = await supabase
          .from('policies')
          .update({ content, title, is_active: isActive, updated_at: new Date().toISOString() })
          .eq('id', existing.id);
        if (error) throw error;
      } else {
        const { error } = await supabase
          .from('policies')
          .insert({ policy_type: activeTab, content, title, is_active: isActive });
        if (error) throw error;
      }
      await fetchPolicies();
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (error) {
      console.error('Error saving policy:', error);
      showAlert('Error', 'Failed to save policy. Please try again.', 'error');
    } finally {
      setSaving(false);
    }
  };

  const escapeHtml = (text: string): string =>
    text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  const sanitizeHtml = (html: string): string =>
    html
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/\bon\w+\s*=\s*["'][^"']*["']/gi, '')
      .replace(/javascript\s*:/gi, '');

  const renderMarkdown = (md: string) => {
    const escaped = escapeHtml(md);
    let html = escaped
      .replace(/^### (.+)$/gm, '<h3>$1</h3>')
      .replace(/^## (.+)$/gm, '<h2>$1</h2>')
      .replace(/^# (.+)$/gm, '<h1>$1</h1>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br/>');

    html = html.replace(/(<li>.*?<\/li>)+/gs, (match) => `<ul>${match}</ul>`);

    return sanitizeHtml(`<p>${html}</p>`);
  };

  const tabs = [
    { id: 'privacy_policy' as const, label: 'Privacy Policy', icon: <Shield size={16} /> },
    { id: 'terms_conditions' as const, label: 'Terms & Conditions', icon: <FileText size={16} /> },
  ];

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '50vh' }}>
        <Loader size={24} className="spin" style={{ color: 'hsl(var(--accent))' }} />
      </div>
    );
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', color: 'hsl(var(--text-main))' }}>
            Legal Policies
          </h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginTop: '0.25rem' }}>
            Manage Privacy Policy and Terms & Conditions shown to users
          </p>
        </div>
        <button
          className="btn btn-primary"
          onClick={handleSave}
          disabled={saving}
          style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}
        >
          {saving ? <Loader size={16} className="spin" /> : <Save size={16} />}
          {saving ? 'Saving...' : saved ? 'Saved!' : 'Save Changes'}
        </button>
      </div>

      {/* Tabs */}
      <div style={{ display: 'flex', gap: '0.5rem', marginBottom: '1.25rem' }}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              padding: '0.6rem 1.2rem',
              borderRadius: '8px',
              border: 'none',
              cursor: 'pointer',
              fontSize: '0.85rem',
              fontWeight: 600,
              fontFamily: 'var(--font-body)',
              background: activeTab === tab.id ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-card))',
              color: activeTab === tab.id ? 'hsl(var(--accent))' : 'hsl(var(--text-tertiary))',
              transition: 'all 0.15s ease',
            }}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Settings row */}
      <div className="card" style={{ marginBottom: '1rem', padding: '1rem', display: 'flex', alignItems: 'center', gap: '1.5rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <input
            type="checkbox"
            id="is-active"
            checked={isActive}
            onChange={(e) => setIsActive(e.target.checked)}
            style={{ width: '16px', height: '16px', accentColor: 'hsl(var(--accent))' }}
          />
          <label htmlFor="is-active" style={{ fontSize: '0.85rem', color: 'hsl(var(--text-main))', cursor: 'pointer' }}>
            Active (visible to users)
          </label>
        </div>
        <div style={{ flex: 1 }} />
        <button
          onClick={() => setPreviewMode(!previewMode)}
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '0.4rem',
            padding: '0.45rem 0.9rem',
            borderRadius: '8px',
            border: '1px solid hsl(var(--border))',
            background: previewMode ? 'hsl(var(--accent-dim))' : 'transparent',
            color: previewMode ? 'hsl(var(--accent))' : 'hsl(var(--text-tertiary))',
            cursor: 'pointer',
            fontSize: '0.8rem',
            fontWeight: 500,
            fontFamily: 'var(--font-body)',
          }}
        >
          {previewMode ? <Edit3 size={14} /> : <Eye size={14} />}
          {previewMode ? 'Edit' : 'Preview'}
        </button>
      </div>

      {/* Editor / Preview */}
      <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
        {previewMode ? (
          <div style={{ padding: '2rem' }}>
            <div
              className="markdown-preview"
              dangerouslySetInnerHTML={{ __html: renderMarkdown(content) }}
              style={{
                color: 'hsl(var(--text-main))',
                lineHeight: 1.7,
                fontSize: '0.9rem',
              }}
            />
          </div>
        ) : (
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={`Enter ${activeTab === 'privacy_policy' ? 'Privacy Policy' : 'Terms & Conditions'} content in Markdown...`}
            style={{
              width: '100%',
              minHeight: '500px',
              padding: '1.5rem',
              border: 'none',
              outline: 'none',
              resize: 'vertical',
              fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
              fontSize: '0.85rem',
              lineHeight: 1.7,
              color: 'hsl(var(--text-main))',
              background: 'hsl(var(--bg-card))',
              tabSize: 2,
            }}
          />
        )}
      </div>

      {/* Help text */}
      <div style={{ marginTop: '1rem', padding: '1rem', background: 'hsl(var(--bg-card))', borderRadius: '8px', border: '1px solid hsl(var(--border))' }}>
        <p style={{ fontSize: '0.8rem', color: 'hsl(var(--text-tertiary))', margin: 0, lineHeight: 1.6 }}>
          <strong style={{ color: 'hsl(var(--text-secondary))' }}>Markdown supported:</strong>{' '}
          # Heading 1 &middot; ## Heading 2 &middot; ### Heading 3 &middot; **bold** &middot; *italic* &middot; - list item
        </p>
      </div>

      <style>{`
        .markdown-preview h1 { font-size: 1.5rem; font-weight: 700; margin: 1.5rem 0 0.75rem; color: hsl(var(--text-main)); }
        .markdown-preview h2 { font-size: 1.2rem; font-weight: 600; margin: 1.25rem 0 0.5rem; color: hsl(var(--text-main)); }
        .markdown-preview h3 { font-size: 1rem; font-weight: 600; margin: 1rem 0 0.5rem; color: hsl(var(--text-main)); }
        .markdown-preview p { margin: 0.5rem 0; }
        .markdown-preview ul { margin: 0.5rem 0; padding-left: 1.5rem; }
        .markdown-preview li { margin: 0.25rem 0; }
        .markdown-preview em { color: hsl(var(--text-tertiary)); }
      `}</style>
      {AlertComponent}
    </div>
  );
};
