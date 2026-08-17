import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { BrainCircuit, Save, Loader, ShieldAlert, Check, Plus, X } from 'lucide-react';
import { useAlert } from '../components/use-alert';

type Provider = 'gemini' | 'groq' | 'cloudflare';

const CLOUDFLARE_MODELS = [
  { value: '@cf/meta/llama-4-scout-17b-16e-instruct', label: 'Llama 4 Scout (17B) — Vision, 131k ctx' },
  { value: '@cf/meta/llama-3.2-11b-vision-instruct', label: 'Llama 3.2 Vision (11B) — Vision, 128k ctx' },
  { value: '@cf/google/gemma-4-26b-a4b-it', label: 'Gemma 4 (26B) — Vision, 256k ctx' },
  { value: '@cf/moonshotai/kimi-k2.5', label: 'Kimi K2.5 — Vision, 262k ctx' },
  { value: '@cf/moonshotai/kimi-k2.6', label: 'Kimi K2.6 — Vision, 262k ctx' },
];

interface APIKeyItem {
  id: string;
  value: string;
  masked: string;
  isConfigured: boolean;
  originalValue?: string;
}

export const AISettings: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  const [geminiKeys, setGeminiKeys] = useState<APIKeyItem[]>([]);
  const [groqKeys, setGroqKeys] = useState<APIKeyItem[]>([]);
  const [cloudflareKeys, setCloudflareKeys] = useState<APIKeyItem[]>([]);
  
  const [cloudflareAccountId, setCloudflareAccountId] = useState('');

  const [geminiModel, setGeminiModel] = useState('gemini-1.5-flash');
  const [groqModel, setGroqModel] = useState('meta-llama/llama-4-scout-17b-16e-instruct');
  const [cloudflareModel, setCloudflareModel] = useState(CLOUDFLARE_MODELS[0].value);

  const [activeProvider, setActiveProvider] = useState<Provider>('gemini');

  const { alert, AlertComponent } = useAlert();

  useEffect(() => {
    fetchConfigs();
  }, []);

  const fetchConfigs = async () => {
    try {
      setLoading(true);

      const [
        geminiKeysRes, 
        groqKeysRes, 
        cloudflareKeysRes,
        singleGeminiKeyRes,
        singleGroqKeyRes,
        singleCloudflareKeyRes,
        geminiModelRes, 
        groqModelRes, 
        providerRes, 
        cfModelRes, 
        cfAccountIdRes
      ] = await Promise.all([
        supabase.rpc('get_ai_key', { p_key_name: 'gemini_api_keys' }),
        supabase.rpc('get_ai_key', { p_key_name: 'groq_api_keys' }),
        supabase.rpc('get_ai_key', { p_key_name: 'cloudflare_api_keys' }),
        supabase.rpc('get_ai_key', { p_key_name: 'gemini_api_key' }),
        supabase.rpc('get_ai_key', { p_key_name: 'groq_api_key' }),
        supabase.rpc('get_ai_key', { p_key_name: 'cloudflare_api_key' }),
        supabase.rpc('get_ai_key', { p_key_name: 'gemini_model' }),
        supabase.rpc('get_ai_key', { p_key_name: 'groq_model' }),
        supabase.rpc('get_ai_key', { p_key_name: 'active_ai_provider' }),
        supabase.rpc('get_ai_key', { p_key_name: 'cloudflare_model' }),
        supabase.rpc('get_ai_key', { p_key_name: 'cloudflare_account_id' }),
      ]);

      const loadKeysList = (arrayRes: any, singleRes: any): APIKeyItem[] => {
        let keys: string[] = [];
        if (arrayRes.data && arrayRes.data.startsWith('[')) {
          try {
            keys = JSON.parse(arrayRes.data);
          } catch (_) {}
        }
        
        if (keys.length === 0 && singleRes.data && singleRes.data.trim()) {
          keys = [singleRes.data.trim()];
        }

        return keys.map((k, index) => {
          const suffix = k.length > 4 ? k.substring(k.length - 4) : '';
          return {
            id: `loaded-${index}-${Math.random()}`,
            value: '',
            masked: k.length > 4 ? `••••••••••••${suffix}` : '••••••••••••',
            isConfigured: true,
            originalValue: k
          };
        });
      };

      const gKeys = loadKeysList(geminiKeysRes, singleGeminiKeyRes);
      setGeminiKeys(gKeys.length > 0 ? gKeys : [{ id: `init-${Math.random()}`, value: '', masked: '', isConfigured: false }]);

      const grKeys = loadKeysList(groqKeysRes, singleGroqKeyRes);
      setGroqKeys(grKeys.length > 0 ? grKeys : [{ id: `init-${Math.random()}`, value: '', masked: '', isConfigured: false }]);

      const cfKeys = loadKeysList(cloudflareKeysRes, singleCloudflareKeyRes);
      setCloudflareKeys(cfKeys.length > 0 ? cfKeys : [{ id: `init-${Math.random()}`, value: '', masked: '', isConfigured: false }]);

      if (geminiModelRes.data) setGeminiModel(geminiModelRes.data);
      if (groqModelRes.data) setGroqModel(groqModelRes.data);
      if (cfModelRes.data) setCloudflareModel(cfModelRes.data);
      if (cfAccountIdRes.data) setCloudflareAccountId(cfAccountIdRes.data);
      if (providerRes.data) setActiveProvider(providerRes.data as Provider);

    } catch (err) {
      console.error('Error fetching AI configurations:', err);
    } finally {
      setLoading(false);
    }
  };

  const addKeyField = (provider: Provider) => {
    const newField = { id: `new-${Math.random()}`, value: '', masked: '', isConfigured: false };
    if (provider === 'gemini') {
      setGeminiKeys([...geminiKeys, newField]);
    } else if (provider === 'groq') {
      setGroqKeys([...groqKeys, newField]);
    } else if (provider === 'cloudflare') {
      setCloudflareKeys([...cloudflareKeys, newField]);
    }
  };

  const removeKeyField = (provider: Provider, id: string) => {
    const filterList = (list: APIKeyItem[]) => {
      const filtered = list.filter(k => k.id !== id);
      return filtered.length > 0 ? filtered : [{ id: `init-${Math.random()}`, value: '', masked: '', isConfigured: false }];
    };

    if (provider === 'gemini') {
      setGeminiKeys(filterList(geminiKeys));
    } else if (provider === 'groq') {
      setGroqKeys(filterList(groqKeys));
    } else if (provider === 'cloudflare') {
      setCloudflareKeys(filterList(cloudflareKeys));
    }
  };

  const updateKeyValue = (provider: Provider, id: string, val: string) => {
    const update = (list: APIKeyItem[]) => list.map(k => k.id === id ? { ...k, value: val } : k);
    if (provider === 'gemini') {
      setGeminiKeys(update(geminiKeys));
    } else if (provider === 'groq') {
      setGroqKeys(update(groqKeys));
    } else if (provider === 'cloudflare') {
      setCloudflareKeys(update(cloudflareKeys));
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSaved(false);

    try {
      const getKeysToSave = (list: APIKeyItem[]) => {
        return list
          .map(k => k.value.trim() ? k.value.trim() : (k.isConfigured ? k.originalValue : ''))
          .filter(k => k !== undefined && k !== '') as string[];
      };

      const activeGeminiKeys = getKeysToSave(geminiKeys);
      const activeGroqKeys = getKeysToSave(groqKeys);
      const activeCloudflareKeys = getKeysToSave(cloudflareKeys);

      // Save arrays as JSON strings
      const { error: gKeysErr } = await supabase.rpc('set_ai_key', {
        p_key_name: 'gemini_api_keys',
        p_key_value: JSON.stringify(activeGeminiKeys),
      });
      if (gKeysErr) throw gKeysErr;

      const { error: grKeysErr } = await supabase.rpc('set_ai_key', {
        p_key_name: 'groq_api_keys',
        p_key_value: JSON.stringify(activeGroqKeys),
      });
      if (grKeysErr) throw grKeysErr;

      const { error: cfKeysErr } = await supabase.rpc('set_ai_key', {
        p_key_name: 'cloudflare_api_keys',
        p_key_value: JSON.stringify(activeCloudflareKeys),
      });
      if (cfKeysErr) throw cfKeysErr;

      // Save primary single keys for backward compatibility
      await supabase.rpc('set_ai_key', {
        p_key_name: 'gemini_api_key',
        p_key_value: activeGeminiKeys.length > 0 ? activeGeminiKeys[0] : '',
      });

      await supabase.rpc('set_ai_key', {
        p_key_name: 'groq_api_key',
        p_key_value: activeGroqKeys.length > 0 ? activeGroqKeys[0] : '',
      });

      await supabase.rpc('set_ai_key', {
        p_key_name: 'cloudflare_api_key',
        p_key_value: activeCloudflareKeys.length > 0 ? activeCloudflareKeys[0] : '',
      });

      if (cloudflareAccountId.trim()) {
        const { error } = await supabase.rpc('set_ai_key', {
          p_key_name: 'cloudflare_account_id',
          p_key_value: cloudflareAccountId.trim(),
        });
        if (error) throw error;
      }

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
          p_key_name: 'cloudflare_model',
          p_key_value: cloudflareModel.trim(),
        }),
        supabase.rpc('set_ai_key', {
          p_key_name: 'active_ai_provider',
          p_key_value: activeProvider,
        }),
      ]);

      await fetchConfigs();
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err: any) {
      console.error('Error saving configurations:', err);
      alert('Error', { description: 'Failed to save AI configuration: ' + err.message, variant: 'danger' });
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

  const providerRadioStyle = (provider: Provider) => ({
    flex: 1,
    display: 'flex' as const,
    alignItems: 'center' as const,
    gap: '0.625rem',
    padding: '1rem',
    borderRadius: '8px',
    border: activeProvider === provider ? '2px solid hsl(var(--accent))' : '1px solid hsl(var(--border))',
    background: activeProvider === provider ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-card))',
    cursor: 'pointer' as const,
    fontWeight: 500,
    color: activeProvider === provider ? 'hsl(var(--accent))' : 'hsl(var(--text-secondary))',
    transition: 'all 0.15s ease'
  });

  const inputStyle = {
    padding: '0.6rem 0.8rem',
    borderRadius: '8px',
    border: '1px solid hsl(var(--border))',
    backgroundColor: 'hsl(var(--bg-main))',
    color: 'hsl(var(--text-main))'
  };

  const sectionOpacity = (provider: Provider) => activeProvider === provider ? 1 : 0.6;

  return (
    <div style={{ maxWidth: '800px', margin: '0 auto' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', color: 'hsl(var(--text-main))', display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
            <BrainCircuit style={{ color: 'hsl(var(--accent))' }} />
            AI Integration Settings
          </h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginTop: '0.25rem' }}>
            Configure active AI provider credentials and fallback API keys. Keys are automatically cycled as fallbacks if errors occur.
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
            <label style={providerRadioStyle('gemini')}>
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

            <label style={providerRadioStyle('groq')}>
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

            <label style={providerRadioStyle('cloudflare')}>
              <input
                type="radio"
                name="activeProvider"
                value="cloudflare"
                checked={activeProvider === 'cloudflare'}
                onChange={() => setActiveProvider('cloudflare')}
                style={{ accentColor: 'hsl(var(--accent))' }}
              />
              <span>Cloudflare Workers AI</span>
            </label>
          </div>
        </div>

        <hr style={{ border: 'none', borderBottom: '1px solid hsl(var(--border))' }} />

        {/* Gemini Settings Group */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', opacity: sectionOpacity('gemini') }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>Gemini Configurations</h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
            <label style={{ fontSize: '0.85rem', color: 'hsl(var(--text-secondary))', fontWeight: 600 }}>Gemini API Keys</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
              {geminiKeys.map((key, index) => (
                <div key={key.id} style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', width: '70px', flexShrink: 0 }}>
                    {index === 0 ? 'Primary' : `Fallback ${index}`}
                  </span>
                  <input
                    type="password"
                    className="form-control"
                    value={key.value}
                    onChange={(e) => updateKeyValue('gemini', key.id, e.target.value)}
                    placeholder={key.masked || 'Enter Gemini API key'}
                    style={{ ...inputStyle, flex: 1 }}
                    disabled={activeProvider !== 'gemini'}
                  />
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    style={{ padding: '0.55rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                    onClick={() => removeKeyField('gemini', key.id)}
                    disabled={activeProvider !== 'gemini'}
                    title="Remove API Key"
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              style={{ alignSelf: 'flex-start', marginTop: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.75rem' }}
              onClick={() => addKeyField('gemini')}
              disabled={activeProvider !== 'gemini'}
            >
              <Plus size={12} /> Add Fallback Key
            </button>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>Gemini Model ID</label>
            <input
              type="text"
              className="form-control"
              value={geminiModel}
              onChange={(e) => setGeminiModel(e.target.value)}
              placeholder="e.g. gemini-1.5-flash"
              style={inputStyle}
            />
          </div>
        </div>

        <hr style={{ border: 'none', borderBottom: '1px solid hsl(var(--border))' }} />

        {/* Groq Settings Group */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', opacity: sectionOpacity('groq') }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>Groq Configurations</h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
            <label style={{ fontSize: '0.85rem', color: 'hsl(var(--text-secondary))', fontWeight: 600 }}>Groq API Keys</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
              {groqKeys.map((key, index) => (
                <div key={key.id} style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', width: '70px', flexShrink: 0 }}>
                    {index === 0 ? 'Primary' : `Fallback ${index}`}
                  </span>
                  <input
                    type="password"
                    className="form-control"
                    value={key.value}
                    onChange={(e) => updateKeyValue('groq', key.id, e.target.value)}
                    placeholder={key.masked || 'Enter Groq API key'}
                    style={{ ...inputStyle, flex: 1 }}
                    disabled={activeProvider !== 'groq'}
                  />
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    style={{ padding: '0.55rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                    onClick={() => removeKeyField('groq', key.id)}
                    disabled={activeProvider !== 'groq'}
                    title="Remove API Key"
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              style={{ alignSelf: 'flex-start', marginTop: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.75rem' }}
              onClick={() => addKeyField('groq')}
              disabled={activeProvider !== 'groq'}
            >
              <Plus size={12} /> Add Fallback Key
            </button>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>Groq Model ID</label>
            <input
              type="text"
              className="form-control"
              value={groqModel}
              onChange={(e) => setGroqModel(e.target.value)}
              placeholder="e.g. meta-llama/llama-4-scout-17b-16e-instruct"
              style={inputStyle}
            />
          </div>
        </div>

        <hr style={{ border: 'none', borderBottom: '1px solid hsl(var(--border))' }} />

        {/* Cloudflare Settings Group */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', opacity: sectionOpacity('cloudflare') }}>
          <h3 style={{ fontSize: '1rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>Cloudflare Workers AI Configurations</h3>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
            <label style={{ fontSize: '0.85rem', color: 'hsl(var(--text-secondary))', fontWeight: 600 }}>Cloudflare API Tokens</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
              {cloudflareKeys.map((key, index) => (
                <div key={key.id} style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', width: '70px', flexShrink: 0 }}>
                    {index === 0 ? 'Primary' : `Fallback ${index}`}
                  </span>
                  <input
                    type="password"
                    className="form-control"
                    value={key.value}
                    onChange={(e) => updateKeyValue('cloudflare', key.id, e.target.value)}
                    placeholder={key.masked || 'Enter Cloudflare API token'}
                    style={{ ...inputStyle, flex: 1 }}
                    disabled={activeProvider !== 'cloudflare'}
                  />
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    style={{ padding: '0.55rem', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                    onClick={() => removeKeyField('cloudflare', key.id)}
                    disabled={activeProvider !== 'cloudflare'}
                    title="Remove API Token"
                  >
                    <X size={14} />
                  </button>
                </div>
              ))}
            </div>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              style={{ alignSelf: 'flex-start', marginTop: '0.5rem', display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.75rem' }}
              onClick={() => addKeyField('cloudflare')}
              disabled={activeProvider !== 'cloudflare'}
            >
              <Plus size={12} /> Add Fallback Token
            </button>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>Cloudflare Account ID</label>
            <input
              type="text"
              className="form-control"
              value={cloudflareAccountId}
              onChange={(e) => setCloudflareAccountId(e.target.value)}
              placeholder="e.g. abc123def456ghi789"
              style={inputStyle}
            />
            <span style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>
              Found on the Cloudflare dashboard URL or Overview page.
            </span>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>Vision Model</label>
            <select
              className="form-control"
              value={cloudflareModel}
              onChange={(e) => setCloudflareModel(e.target.value)}
              style={{
                ...inputStyle,
                cursor: 'pointer',
                appearance: 'none' as const,
                backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%23999' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E")`,
                backgroundRepeat: 'no-repeat',
                backgroundPosition: 'right 0.75rem center',
                paddingRight: '2rem'
              }}
            >
              {CLOUDFLARE_MODELS.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
            <span style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>
              All models listed support image input for product photo analysis.
            </span>
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
      {AlertComponent}
    </div>
  );
};
