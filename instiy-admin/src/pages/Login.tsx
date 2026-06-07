import React, { useState } from 'react';
import { supabase } from '../supabaseClient';
import { Shield, Mail, Lock, Loader } from 'lucide-react';

interface LoginProps {
  onLoginSuccess: (userId: string) => void;
}

export const Login: React.FC<LoginProps> = ({ onLoginSuccess }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrorMsg('');

    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) throw error;

      if (data?.user) {
        const { data: profile, error: profileError } = await supabase
          .from('users')
          .select('is_admin')
          .eq('id', data.user.id)
          .single();

        if (profileError) {
          await supabase.auth.signOut();
          throw new Error('Failed to verify user permissions.');
        }

        if (!profile?.is_admin) {
          await supabase.auth.signOut();
          throw new Error('Access denied. Admins only.');
        }

        onLoginSuccess(data.user.id);
      }
    } catch (err: any) {
      setErrorMsg(err.message || 'Sign in failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      minHeight: '100vh',
      backgroundColor: 'hsl(var(--bg-main))',
      padding: '1.25rem'
    }}>
      <div className="animated-fade-in" style={{
        width: '100%',
        maxWidth: '380px',
        padding: '2rem',
        backgroundColor: 'hsl(var(--bg-card))',
        border: '1px solid hsl(var(--border))',
        borderRadius: 'var(--radius-md)',
      }}>
        <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
          <div style={{
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: '48px',
            height: '48px',
            borderRadius: '12px',
            background: 'hsl(var(--accent-dim))',
            color: 'hsl(var(--accent))',
            marginBottom: '0.875rem'
          }}>
            <Shield size={24} />
          </div>
          <h2 style={{ fontSize: '1.4rem', fontWeight: 700, marginBottom: '0.25rem', fontFamily: 'var(--font-title)' }}>Instiy Admin</h2>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>Sign in to manage the marketplace</p>
        </div>

        {errorMsg && (
          <div style={{
            padding: '0.6rem 0.85rem',
            borderRadius: 'var(--radius-sm)',
            fontSize: '0.8rem',
            marginBottom: '1.25rem',
            display: 'block',
            fontWeight: 500,
            background: 'hsl(var(--danger-dim))',
            color: 'hsl(var(--danger-hover))',
            border: '1px solid hsl(var(--danger) / 0.2)',
          }}>
            {errorMsg}
          </div>
        )}

        <form onSubmit={handleLogin}>
          <div className="form-group">
            <label className="form-label">Email</label>
            <div style={{ position: 'relative' }}>
              <Mail size={16} style={{
                position: 'absolute',
                left: '10px',
                top: '50%',
                transform: 'translateY(-50%)',
                color: 'hsl(var(--text-tertiary))'
              }} />
              <input
                type="email"
                className="form-control"
                style={{ paddingLeft: '2.25rem' }}
                placeholder="admin@instiy.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                disabled={loading}
              />
            </div>
          </div>

          <div className="form-group" style={{ marginBottom: '1.5rem' }}>
            <label className="form-label">Password</label>
            <div style={{ position: 'relative' }}>
              <Lock size={16} style={{
                position: 'absolute',
                left: '10px',
                top: '50%',
                transform: 'translateY(-50%)',
                color: 'hsl(var(--text-tertiary))'
              }} />
              <input
                type="password"
                className="form-control"
                style={{ paddingLeft: '2.25rem' }}
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                disabled={loading}
              />
            </div>
          </div>

          <button
            type="submit"
            className="btn btn-primary"
            style={{ width: '100%', padding: '0.6rem' }}
            disabled={loading}
          >
            {loading ? (
              <>
                <Loader size={16} className="spin" />
                Signing in...
              </>
            ) : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  );
};
