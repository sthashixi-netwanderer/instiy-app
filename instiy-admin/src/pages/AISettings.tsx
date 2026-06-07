import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { BrainCircuit, Save, Loader, ShieldAlert, Check } from 'lucide-react';

export const AISettings: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  // Form states
  const [geminiKey, setGeminiKey] = useState('');
  const [groqKey, setGroqKey] = useState('');
  const [geminiModel, setGeminiModel] = useState('gemini-1.5-flash');
  const [groqModel, setGroqModel] = useState('llama-3.2-11b-vision-preview');
  const [activeProvider, setActiveProvider] = useState<'gemini' | 'groq'>('gemini');

  // Key presence flags (to show placeholder if key is already stored)
  const [hasGeminiKey, setHasGeminiKey] = useState(false);
  const [hasGroqKey, setHasGroqKey] = useState(false);

  useEffect(() => {
    fetchConfigs();
  }, []);

  const fetchConfigs = async () => {
    try {
      setLoading(true);
      // Fetch key presence and model names
      const { data, error } = await supabase
        .from('ai_configs')
        .select('key_name');

      if (error) throw error;

      if (data) {
        const keys = data.map((d: any) => d.key_name);
        setHasGeminiKey(keys.includes('gemini_api_key'));
        setHasGroqKey(keys.includes('groq_api_key'));
      }

      // Fetch decrypted models and active provider
      // Since models and provider are not highly sensitive, we can read them using get_ai_key RPC or standard select
      const [geminiModelRes, groqModelRes, providerRes] = await Promise.all([
        supabase.rpc('get_ai_key', { p_key_name: 'gemini_model' }),
        supabase.rpc('get_ai_key', { p_key_name: 'groq_model' }),
        supabase.rpc('get_ai_key', { p_key_name: 'active_ai_provider' }),
      ]);

      if (geminiModelRes.data) setGeminiModel(geminiModelRes.data);
      if (groqModelRes.data) setGroqModel(groqModelRes.data);
      if (providerRes.data) setActiveProvider(providerRes.data as 'gemini' | 'groq');

    } catch (err) {
      console.error('Error fetching AI configurations:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSaved(false);

    try {
      // 1. Save Gemini Key if edited
      if (geminiKey.trim()) {
        const { error } = await supabase.rpc('set_ai_key', {
          p_key_name: 'gemini_api_key',
          p_key_value: geminiKey.trim(),
        });
        if (error) throw error;
      }

      // 2. Save Groq Key if edited
      if (groqKey.trim()) {
        const { error } = await supabase.rpc('set_ai_key', {
          p_key_name: 'groq_api_key',
          p_key_value: groqKey.trim(),
        });
        if (error) throw error;
      }

      // 3. Save Model Names and Provider
      await Promise.all([
        supabase.rpc('set_ai_key', {
          p_key_name: 'gemini_model',
          p_key_value: geminiModel.trim(),
        }),
        supabase.rpc('set_ai_key', {
          p_key_name: 'groq_model',
          p_key_value: groqModel.trim(),
        }),
        supabase.rpc('set_ai_key', {
          p_key_name: 'active_ai_provider',
          p_key_value: activeProvider,
        }),
      ]);

      // Clear input fields for safety
      setGeminiKey('');
      setGroqKey('');

      // Refresh list
      await fetchConfigs();
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err: any) {
      console.error('Error saving configurations:', err);
      alert('Failed to save AI configuration: ' + err.message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '50vh' }}>
        <Loader size={24} className="spin" style={{ color: 'hsl(var(--accent))' }} />
      </div>
    );
  }

  return (
    <div style={{ maxWidth: '800px', margin: '0 auto' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', color: 'hsl(var(--text-main))', display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
            <BrainCircuit style={{ color: 'hsl(var(--accent))' }} />
            AI Integration Settings
          </h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginTop: '0.25rem' }}>
            Configure Gemini and Groq model credentials. Keys are encrypted symmetrically before saving.
          </p>
        </div>
      </div>

      <form onSubmit={handleSave} className="card" style={{ padding: '2rem', display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
        
        {/* Active AI Provider selection */}
        <div>
          <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'hsl(var(--text-main))', display: 'block', marginBottom: '0.5rem' }}>
            Active AI Provider
          </label>
          <div style={{ display: 'flex', gap: '1rem' }}>
            <label style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              gap: '0.625rem',
              padding: '1rem',
              borderRadius: '8px',
              border: activeProvider === 'gemini' ? '2px solid hsl(var(--accent))' : '1px solid hsl(var(--border))',
              background: activeProvider === 'gemini' ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-card))',
              cursor: 'pointer',
              fontWeight: 500,
              color: activeProvider === 'gemini' ? 'hsl(var(--accent))' : 'hsl(var(--text-secondary))',
              transition: 'all 0.15s ease'
            }}>
              <input
                type="radio"
                name="activeProvider"
                value="gemini"
                checked={activeProvider === 'gemini'}
                onChange={() => setActiveProvider('gemini')}
                style={{ accentColor: 'hsl(var(--accent))' }}
              />
              <span>Google Gemini API</span>
            </label>
            
            <label style={{
              flex: 1,
              display: 'flex',
              alignItems: 'center',
              gap: '0.625rem',
              padding: '1rem',
              borderRadius: '8px',
              border: activeProvider === 'groq' ? '2px solid hsl(var(--accent))' : '1px solid hsl(var(--border))',
              background: activeProvider === 'groq' ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-card))',
              cursor: 'pointer',
              fontWeight: 500,
              color: activeProvider === 'groq' ? 'hsl(var(--accent))' : 'hsl(var(--text-secondary))',
              transition: 'all 0.15s ease'
            }}>
              <input
                type="radio"
                name="activeProvider"
                value="groq"
                checked={activeProvider === 'groq'}
                onChange={() => setActiveProvider('groq')}
                style={{ accentColor: 'hsl(var(--accent))' }}
              />
              <span>Groq Cloud API</span>
            </label>
          </div>
        </div>

        <hr style={{ border: 'none', borderBottom: '1px solid hsl(var(--border))' }} />

        {/* Gemini Settings Group */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', opacity: activeProvider === 'gemini' ? 1 : 0.6 }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>Gemini Configurations</h3>
          
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              Gemini API Key
            </label>
            <input
              type="password"
              className="form-control"
              value={geminiKey}
              onChange={(e) => setGeminiKey(e.target.value)}
              placeholder={hasGeminiKey ? '•••••••••••••••••••••••••••••••• (Configured)' : 'Enter your Gemini API key'}
              style={{
                padding: '0.6rem 0.8rem',
                borderRadius: '8px',
                border: '1px solid hsl(var(--border))',
                backgroundColor: 'hsl(var(--bg-main))',
                color: 'hsl(var(--text-main))'
              }}
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              Gemini Model ID
            </label>
            <input
              type="text"
              className="form-control"
              value={geminiModel}
              onChange={(e) => setGeminiModel(e.target.value)}
              placeholder="e.g. gemini-1.5-flash"
              style={{
                padding: '0.6rem 0.8rem',
                borderRadius: '8px',
                border: '1px solid hsl(var(--border))',
                backgroundColor: 'hsl(var(--bg-main))',
                color: 'hsl(var(--text-main))'
              }}
            />
          </div>
        </div>

        <hr style={{ border: 'none', borderBottom: '1px solid hsl(var(--border))' }} />

        {/* Groq Settings Group */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', opacity: activeProvider === 'groq' ? 1 : 0.6 }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>Groq Configurations</h3>
          
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              Groq API Key
            </label>
            <input
              type="password"
              className="form-control"
              value={groqKey}
              onChange={(e) => setGroqKey(e.target.value)}
              placeholder={hasGroqKey ? '•••••••••••••••••••••••••••••••• (Configured)' : 'Enter your Groq API key'}
              style={{
                padding: '0.6rem 0.8rem',
                borderRadius: '8px',
                border: '1px solid hsl(var(--border))',
                backgroundColor: 'hsl(var(--bg-main))',
                color: 'hsl(var(--text-main))'
              }}
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              Groq Model ID
            </label>
            <input
              type="text"
              className="form-control"
              value={groqModel}
              onChange={(e) => setGroqModel(e.target.value)}
              placeholder="e.g. llama-3.2-11b-vision-preview"
              style={{
                padding: '0.6rem 0.8rem',
                borderRadius: '8px',
                border: '1px solid hsl(var(--border))',
                backgroundColor: 'hsl(var(--bg-main))',
                color: 'hsl(var(--text-main))'
              }}
            />
          </div>
        </div>

        {/* Warning Badge */}
        <div style={{
          display: 'flex',
          alignItems: 'flex-start',
          gap: '0.625rem',
          padding: '0.875rem 1.25rem',
          backgroundColor: 'hsla(var(--destructive-rgb), 0.08)',
          borderRadius: '8px',
          border: '1px solid hsla(var(--destructive-rgb), 0.2)',
          color: 'hsl(var(--destructive))',
          fontSize: '0.8rem'
        }}>
          <ShieldAlert size={18} style={{ flexShrink: 0, marginTop: '2px' }} />
          <div>
            <strong>Security warning:</strong> API keys are encrypted at-rest using pg_sym_encrypt with a database-level secure salt. Make sure your database contains the AI configs migration for decryption to function properly.
          </div>
        </div>

        {/* Submit */}
        <button
          type="submit"
          className="btn btn-primary"
          disabled={saving}
          style={{
            padding: '0.75rem',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '0.5rem',
            fontWeight: 600,
            fontSize: '0.875rem',
            width: '100%',
            marginTop: '0.5rem'
          }}
        >
          {saving ? (
            <Loader size={16} className="spin" />
          ) : saved ? (
            <Check size={16} />
          ) : (
            <Save size={16} />
          )}
          {saving ? 'Saving Configs...' : saved ? 'Configs Saved Successfully!' : 'Save Configurations'}
        </button>

      </form>
    </div>
  );
};
