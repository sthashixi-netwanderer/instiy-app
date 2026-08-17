import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { MapPin, Save, Loader, Check, Activity, ShieldAlert } from 'lucide-react';
import { useAlert } from '../components/use-alert';

export const GPSConfig: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const { showAlert, AlertComponent } = useAlert();

  const [apiUrl, setApiUrl] = useState('');
  const [apiToken, setApiToken] = useState('');

  const [healthStatus, setHealthStatus] = useState<'idle' | 'checking' | 'online' | 'offline'>('idle');
  const [healthMessage, setHealthMessage] = useState('');
  const [healthCoords, setHealthCoords] = useState<{ lat: string; lng: string } | null>(null);

  useEffect(() => {
    fetchConfigs();
  }, []);

  const fetchConfigs = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('ghanapost_config')
        .select('*');

      if (error) throw error;

      if (data) {
        const urlItem = data.find((d: any) => d.key === 'api_url');
        const tokenItem = data.find((d: any) => d.key === 'api_token');
        if (urlItem) setApiUrl(urlItem.value);
        if (tokenItem) setApiToken(tokenItem.value);
      }
    } catch (err) {
      console.error('Error fetching GPS configurations:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSaved(false);

    try {
      const { error } = await supabase
        .from('ghanapost_config')
        .upsert([
          { key: 'api_url', value: apiUrl.trim() },
          { key: 'api_token', value: apiToken.trim() }
        ]);

      if (error) throw error;
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err: any) {
      showAlert('Error', 'Failed to save GPS configuration: ' + err.message, 'error');
    } finally {
      setSaving(false);
    }
  };

  const runHealthCheck = async () => {
    if (!apiUrl.trim()) {
      setHealthStatus('offline');
      setHealthMessage('API Endpoint URL cannot be empty.');
      return;
    }

    setHealthStatus('checking');
    setHealthMessage('');
    setHealthCoords(null);

    try {
      const testAddress = 'GA-123-4567';
      const res = await fetch(`${apiUrl.trim()}?address=${testAddress}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${apiToken.trim()}`,
          'Content-Type': 'application/json'
        }
      });

      const text = await res.text();
      let data: any = {};
      try {
        data = JSON.parse(text);
      } catch (_) {
        // Raw text response
      }

      const resultObj = data.Result || data.result || data;
      if (res.ok && (resultObj.GPSName || resultObj.CenterLatitude || data.GPSName || data.CenterLatitude)) {
        setHealthStatus('online');
        const gpsName = resultObj.GPSName || data.GPSName || testAddress;
        const lat = resultObj.CenterLatitude || data.CenterLatitude || 'N/A';
        const lng = resultObj.CenterLongitude || data.CenterLongitude || 'N/A';
        setHealthMessage(`Online! Responded with address details: Digital Address: ${gpsName}, Latitude: ${lat}, Longitude: ${lng}`);
        if (lat !== 'N/A' && lng !== 'N/A') {
          setHealthCoords({ lat: lat.toString(), lng: lng.toString() });
        }
      } else {
        setHealthStatus('offline');
        setHealthCoords(null);
        setHealthMessage(`Error status ${res.status}: ${data.Message || data.message || text || res.statusText}`);
      }
    } catch (err: any) {
      setHealthStatus('offline');
      setHealthCoords(null);
      // Gracefully handle browser CORS issues
      if (err instanceof TypeError && err.message.toLowerCase().includes('failed to fetch')) {
        setHealthStatus('offline');
        setHealthMessage(
          'Failed to connect. This is likely due to a CORS restriction in the browser. ' +
          'Note: The Ghana Post GPS Mijoride API does not support web browser direct calls (CORS). ' +
          'However, the mobile Flutter application bypassing CORS will function correctly with these credentials if they are valid. ' +
          'Please verify the endpoint URL and JWT token manually.'
        );
      } else {
        setHealthMessage(`Connection failed: ${err.message || err}`);
      }
    }
  };

  const cardStyle: React.CSSProperties = {
    backgroundColor: 'hsl(var(--bg-sidebar))',
    border: '1px solid hsl(var(--border))',
    borderRadius: '12px',
    padding: '1.5rem',
    display: 'flex',
    flexDirection: 'column',
    gap: '1.25rem',
    marginBottom: '1.5rem'
  };

  const inputStyle: React.CSSProperties = {
    width: '100%',
    padding: '0.625rem 0.875rem',
    borderRadius: '6px',
    border: '1px solid hsl(var(--border))',
    backgroundColor: 'hsl(var(--bg-main))',
    color: 'hsl(var(--text-main))',
    fontSize: '0.875rem',
    outline: 'none'
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '60vh' }}>
        <Loader className="spin" size={24} style={{ color: 'hsl(var(--accent))' }} />
      </div>
    );
  }

  return (
    <div style={{ padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', marginBottom: '1.5rem' }}>
        <MapPin size={28} style={{ color: 'hsl(var(--accent))' }} />
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, color: 'hsl(var(--text-main))', margin: 0 }}>
            Ghana Post GPS Configuration
          </h1>
          <p style={{ fontSize: '0.875rem', color: 'hsl(var(--text-secondary))', margin: 0 }}>
            Configure and test the integration for Ghana Post digital address lookup.
          </p>
        </div>
      </div>

      <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
        <div style={cardStyle}>
          <h2 style={{ fontSize: '1.1rem', fontWeight: 600, color: 'hsl(var(--text-main))', margin: 0 }}>
            API Configurations
          </h2>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              GhanaPost API Endpoint URL
            </label>
            <input
              type="text"
              className="form-control"
              value={apiUrl}
              onChange={(e) => setApiUrl(e.target.value)}
              placeholder="e.g. https://mijoride.ghanapostgps.com/user/get_address"
              style={inputStyle}
              required
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.35rem' }}>
            <label style={{ fontSize: '0.8rem', color: 'hsl(var(--text-secondary))', fontWeight: 500 }}>
              Bearer Authentication Token (JWT)
            </label>
            <textarea
              className="form-control"
              value={apiToken}
              onChange={(e) => setApiToken(e.target.value)}
              placeholder="Enter JWT Token (e.g. eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...)"
              style={{ ...inputStyle, minHeight: '80px', fontFamily: 'monospace' }}
              required
            />
          </div>
        </div>

        {/* Realtime Health Check Card */}
        <div style={{
          ...cardStyle,
          borderColor: healthStatus === 'online' ? 'hsla(142, 70%, 45%, 0.4)' : healthStatus === 'offline' ? 'hsla(0, 84%, 60%, 0.4)' : 'hsl(var(--border))'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 600, color: 'hsl(var(--text-main))', margin: 0 }}>
              Real-time API Health Check
            </h2>
            {healthStatus === 'online' && (
              <span style={{ fontSize: '0.75rem', fontWeight: 600, padding: '0.25rem 0.5rem', borderRadius: '9999px', backgroundColor: 'hsla(142, 70%, 45%, 0.1)', color: 'hsl(142, 76%, 36%)', border: '1px solid hsla(142, 70%, 45%, 0.2)' }}>
                Online
              </span>
            )}
            {healthStatus === 'offline' && (
              <span style={{ fontSize: '0.75rem', fontWeight: 600, padding: '0.25rem 0.5rem', borderRadius: '9999px', backgroundColor: 'hsla(0, 84%, 60%, 0.1)', color: 'hsl(0, 84%, 60%)', border: '1px solid hsla(0, 84%, 60%, 0.2)' }}>
                Down / Configuration Error
              </span>
            )}
          </div>
          <p style={{ fontSize: '0.85rem', color: 'hsl(var(--text-secondary))', margin: 0 }}>
            Query the configured Ghana Post GPS server dynamically using a test address (GA-123-4567) to test connectivity.
          </p>

          <button
            type="button"
            className="btn btn-secondary"
            onClick={runHealthCheck}
            disabled={healthStatus === 'checking'}
            style={{
              padding: '0.5rem 1rem',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.5rem',
              fontWeight: 500,
              fontSize: '0.85rem',
              alignSelf: 'flex-start'
            }}
          >
            {healthStatus === 'checking' ? <Loader size={14} className="spin" /> : <Activity size={14} />}
            {healthStatus === 'checking' ? 'Testing Connection...' : 'Run Real-time Test'}
          </button>

          {healthMessage && (
            <div style={{
              padding: '0.75rem 1rem',
              borderRadius: '8px',
              backgroundColor: healthStatus === 'online' ? 'hsla(142, 70%, 45%, 0.05)' : 'hsla(0, 84%, 60%, 0.05)',
              color: healthStatus === 'online' ? 'hsl(142, 76%, 36%)' : 'hsl(0, 84%, 60%)',
              border: `1px solid ${healthStatus === 'online' ? 'hsla(142, 70%, 45%, 0.15)' : 'hsla(0, 84%, 60%, 0.15)'}`,
              fontSize: '0.8rem',
              lineHeight: 1.5
            }}>
              {healthMessage}
            </div>
          )}

          {healthCoords && (
            <div style={{ marginTop: '0.5rem', width: '100%' }}>
              <iframe
                title="Google Map Preview"
                width="100%"
                height="300"
                style={{ border: 0, borderRadius: '8px' }}
                src={`https://maps.google.com/maps?q=${healthCoords.lat},${healthCoords.lng}&z=15&output=embed`}
                allowFullScreen
              ></iframe>
            </div>
          )}
        </div>

        {/* Info Box */}
        <div style={{
          display: 'flex',
          alignItems: 'flex-start',
          gap: '0.625rem',
          padding: '0.875rem 1.25rem',
          backgroundColor: 'hsla(var(--accent-dim-rgb), 0.08)',
          borderRadius: '8px',
          border: '1px solid hsl(var(--border))',
          color: 'hsl(var(--text-tertiary))',
          fontSize: '0.8rem'
        }}>
          <ShieldAlert size={18} style={{ flexShrink: 0, marginTop: '2px', color: 'hsl(var(--accent))' }} />
          <div>
            The credentials set here are dynamically fetched by user profile settings inside the mobile app to geolocate store digital addresses (e.g. GA-492-8490) and embed coordinates on Google Maps.
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
          {saving ? 'Saving Configs...' : saved ? 'Configurations Saved Successfully!' : 'Save Configurations'}
        </button>
      </form>
      {AlertComponent}
    </div>
  );
};
