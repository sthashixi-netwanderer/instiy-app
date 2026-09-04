import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import {
  Gift,
  Save,
  Loader,
  Check,
  RotateCcw,
  Users,
  PackageCheck,
  Star,
  BadgeCheck,
} from 'lucide-react';
import { formatGhs } from '../utils/format';
import { useAlert, useConfirm } from '../components/use-alert';

interface ReferralRow {
  id: string;
  status: string;
  points_awarded: number;
  referee_points: number;
  referee_awarded_at: string | null;
  created_at: string;
  qualified_at: string | null;
  code_used: string;
  referrer: { full_name: string | null; email: string | null } | null;
  referred: { full_name: string | null; email: string | null } | null;
}

export const ReferralSettings: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const [enabled, setEnabled] = useState(true);
  const [minPurchase, setMinPurchase] = useState(50);
  const [pointsPerReferral, setPointsPerReferral] = useState(500);

  const [totalReferrals, setTotalReferrals] = useState(0);
  const [qualifiedReferrals, setQualifiedReferrals] = useState(0);
  const [pointsAwarded, setPointsAwarded] = useState(0);
  const [recent, setRecent] = useState<ReferralRow[]>([]);
  const [pendingReferee, setPendingReferee] = useState<ReferralRow[]>([]);
  const [awardingId, setAwardingId] = useState<string | null>(null);
  const { alert, AlertComponent } = useAlert();
  const { confirm, ConfirmComponent } = useConfirm();

  useEffect(() => {
    fetchAll();
  }, []);

  const fetchAll = async () => {
    try {
      setLoading(true);
      await Promise.all([
        fetchConfig(),
        fetchStats(),
        fetchRecent(),
        fetchPendingReferee(),
      ]);
    } catch (err) {
      console.error('Error loading referral data:', err);
      setErrorMsg('Failed to load referral data.');
    } finally {
      setLoading(false);
    }
  };

  const fetchConfig = async () => {
    const { data, error } = await supabase
      .from('platform_settings')
      .select('value')
      .eq('key', 'referral_program')
      .maybeSingle();
    if (error) throw error;
    if (data?.value) {
      const v = data.value as Record<string, unknown>;
      if (v.enabled != null) setEnabled(Boolean(v.enabled));
      if (v.min_purchase_amount_ghs != null)
        setMinPurchase(Number(v.min_purchase_amount_ghs));
      if (v.points_per_referral != null)
        setPointsPerReferral(Number(v.points_per_referral));
    }
  };

  const fetchStats = async () => {
    const [totalRes, qualifiedRes, pointsRes] = await Promise.all([
      supabase
        .from('referrals')
        .select('*', { count: 'exact', head: true }),
      supabase
        .from('referrals')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'qualified'),
      supabase.from('referrals').select('points_awarded'),
    ]);
    setTotalReferrals(totalRes.count ?? 0);
    setQualifiedReferrals(qualifiedRes.count ?? 0);
    setPointsAwarded(
      (pointsRes.data ?? []).reduce(
        (sum, r) => sum + (r.points_awarded ?? 0),
        0
      )
    );
  };

  const fetchRecent = async () => {
    const { data, error } = await supabase
      .from('referrals')
      .select(
        `id, status, points_awarded, referee_points, referee_awarded_at,
         created_at, qualified_at, code_used,
         referrer:referrer_id ( full_name, email ),
         referred:referred_id ( full_name, email )`
      )
      .order('created_at', { ascending: false })
      .limit(10);
    if (error) throw error;
    setRecent((data ?? []) as unknown as ReferralRow[]);
  };

  const fetchPendingReferee = async () => {
    const { data, error } = await supabase
      .from('referrals')
      .select(
        `id, status, points_awarded, referee_points, referee_awarded_at,
         created_at, qualified_at, code_used,
         referrer:referrer_id ( full_name, email ),
         referred:referred_id ( full_name, email )`
      )
      .eq('status', 'qualified')
      .is('referee_awarded_at', null)
      .gt('referee_points', 0)
      .order('qualified_at', { ascending: true });
    if (error) throw error;
    setPendingReferee((data ?? []) as unknown as ReferralRow[]);
  };

  const handleAwardReferee = (row: ReferralRow) => {
    const name = displayName(row.referred);
    confirm(
      `Award ${row.referee_points.toLocaleString()} pts to ${name}?`,
      async () => {
        setAwardingId(row.id);
        try {
          const { data, error } = await supabase.rpc(
            'award_referee_points',
            { p_referral_id: row.id }
          );
          if (error) throw error;
          const awarded = Number(data ?? 0);
          if (awarded > 0) {
            alert('Points awarded', {
              description: `${awarded.toLocaleString()} pts credited to ${name}.`,
              variant: 'success',
            });
          } else {
            alert('Nothing to award', {
              description: 'This reward was already released.',
              variant: 'info',
            });
          }
          await Promise.all([fetchPendingReferee(), fetchRecent(), fetchStats()]);
        } catch (err) {
          console.error('Error awarding referee points:', err);
          alert('Award failed', {
            description: (err as Error)?.message ?? 'Check your connection and try again.',
            variant: 'danger',
          });
        } finally {
          setAwardingId(null);
        }
      },
      {
        description:
          'The referred user earned half of the referrer reward once their ' +
          'order was delivered. This credits their balance immediately.',
        confirmLabel: 'Award points',
      }
    );
  };

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    if (minPurchase < 0 || pointsPerReferral < 0) {
      setErrorMsg('Amounts cannot be negative.');
      return;
    }
    setSaving(true);
    setSaved(false);
    setErrorMsg(null);

    try {
      const { error } = await supabase
        .from('platform_settings')
        .upsert(
          {
            key: 'referral_program',
            value: {
              enabled,
              min_purchase_amount_ghs: minPurchase,
              points_per_referral: pointsPerReferral,
            },
          },
          { onConflict: 'key' }
        );
      if (error) throw error;
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err) {
      console.error('Error saving referral settings:', err);
      setErrorMsg('Failed to save. Check your connection and try again.');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    setEnabled(true);
    setMinPurchase(50);
    setPointsPerReferral(500);
  };

  const fmtDate = (iso: string | null) =>
    iso ? new Date(iso).toLocaleDateString() : '—';

  const displayName = (
    u: { full_name: string | null; email: string | null } | null
  ) => u?.full_name || u?.email || 'Unknown user';

  if (loading) {
    return (
      <div className="page-loading">
        <Loader size={24} className="spin" />
        <span>Loading referral settings...</span>
      </div>
    );
  }

  const statCards = [
    {
      label: 'Total Referrals',
      value: String(totalReferrals),
      detail: `${totalReferrals - qualifiedReferrals} pending qualification`,
      icon: <Users size={20} />,
      iconBg: 'hsl(var(--accent-dim))',
    },
    {
      label: 'Completed Referrals',
      value: String(qualifiedReferrals),
      detail: 'Qualified via delivered orders',
      icon: <PackageCheck size={20} />,
      iconBg: 'hsl(142 60% 35% / 0.15)',
    },
    {
      label: 'Referee Rewards Pending',
      value: String(pendingReferee.length),
      detail: 'Qualified — awaiting admin approval',
      icon: <BadgeCheck size={20} />,
      iconBg: 'hsl(200 80% 50% / 0.15)',
    },
    {
      label: 'Points Awarded',
      value: pointsAwarded.toLocaleString(),
      detail: `${formatGhs(minPurchase)}+ delivered order = ${pointsPerReferral} pts`,
      icon: <Star size={20} />,
      iconBg: 'hsl(38 92% 50% / 0.15)',
    },
  ];

  return (
    <div>
      <div className="page-header">
        <div>
          <h1>Referrals</h1>
          <p className="page-subtitle">
            Configure the referral program and monitor referral activity
          </p>
        </div>
      </div>

      <div className="dashboard-grid">
        {statCards.map((card) => (
          <div key={card.label} className="card">
            <div className="card-title">{card.label}</div>
            <div className="card-value">{card.value}</div>
            <div
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '0.5rem',
                fontSize: '0.75rem',
                color: 'hsl(var(--text-tertiary))',
                marginTop: '0.5rem',
              }}
            >
              <span
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: '32px',
                  height: '32px',
                  borderRadius: '8px',
                  background: card.iconBg,
                  color: 'hsl(var(--accent))',
                }}
              >
                {card.icon}
              </span>
              {card.detail}
            </div>
          </div>
        ))}
      </div>

      <form onSubmit={handleSave} className="settings-card" style={{ marginTop: '1.25rem' }}>
        <div className="settings-card-header">
          <Gift size={20} />
          <h2>Program Rules</h2>
        </div>

        <div className="form-group">
          <label>Program Status</label>
          <button
            type="button"
            className="btn btn-secondary"
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              borderColor: enabled
                ? 'hsl(142 60% 35% / 0.5)'
                : 'hsl(var(--border))',
              color: enabled ? 'hsl(142 60% 35%)' : 'hsl(var(--text-tertiary))',
            }}
            onClick={() => setEnabled((v) => !v)}
          >
            {enabled ? <Check size={16} /> : <RotateCcw size={16} />}
            {enabled ? 'Enabled — points are being awarded' : 'Disabled — no points awarded'}
          </button>
          <p className="form-hint">
            Disabling pauses all point awards (existing points are kept).
          </p>
        </div>

        <div className="form-group">
          <label>Minimum Delivered Order Amount (GHS)</label>
          <div className="input-with-suffix">
            <input
              type="number"
              step="1"
              min="0"
              value={minPurchase}
              onChange={(e) => setMinPurchase(parseFloat(e.target.value) || 0)}
              className="form-control"
            />
            <span className="input-suffix">GHS</span>
          </div>
          <p className="form-hint">
            A referral qualifies when the referred user's delivered order value
            reaches this amount. Current: {formatGhs(minPurchase)}
          </p>
        </div>

        <div className="form-group">
          <label>Points per Successful Referral</label>
          <div className="input-with-suffix">
            <input
              type="number"
              step="1"
              min="0"
              value={pointsPerReferral}
              onChange={(e) =>
                setPointsPerReferral(parseInt(e.target.value, 10) || 0)
              }
              className="form-control"
            />
            <span className="input-suffix">pts</span>
          </div>
          <p className="form-hint">
            Points awarded to the referrer once the referred user's order is
            delivered and meets the minimum. The referred user earns half of
            this amount, released by an admin from the approval queue below.
            Points are reversed if the order is fully refunded.
          </p>
        </div>

        <div className="settings-card-footer">
          <button
            type="button"
            className="btn btn-secondary"
            onClick={handleReset}
          >
            <RotateCcw size={16} />
            Reset to Defaults
          </button>
          <div className="footer-right">
            {saved && (
              <span className="save-indicator">
                <Check size={16} /> Saved
              </span>
            )}
            <button
              type="submit"
              className="btn btn-primary"
              disabled={saving}
            >
              {saving ? <Loader size={16} className="spin" /> : <Save size={16} />}
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        </div>
      </form>

      <div className="card" style={{ marginTop: '1.25rem' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: '0.75rem',
          }}
        >
          <div>
            <h2 style={{ fontSize: '1rem', fontWeight: 600 }}>
              Referee Rewards — Awaiting Approval{' '}
              <span className="badge badge-warning">
                {pendingReferee.length} pending
              </span>
            </h2>
            <p
              style={{
                fontSize: '0.8rem',
                color: 'hsl(var(--text-tertiary))',
                marginTop: '0.25rem',
              }}
            >
              Referred users earn half of the referrer reward once their
              order is delivered. Release each reward with the Award button.
            </p>
          </div>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={fetchAll}
          >
            <RotateCcw size={14} /> Refresh
          </button>
        </div>
        {pendingReferee.length === 0 ? (
          <p
            style={{
              fontSize: '0.85rem',
              color: 'hsl(var(--text-tertiary))',
              padding: '1rem 0',
            }}
          >
            All caught up — no referee rewards waiting for approval.
          </p>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Referred User</th>
                  <th>Referrer</th>
                  <th>Reward</th>
                  <th>Qualified</th>
                  <th style={{ textAlign: 'right' }}>Action</th>
                </tr>
              </thead>
              <tbody>
                {pendingReferee.map((r) => (
                  <tr key={r.id}>
                    <td>{displayName(r.referred)}</td>
                    <td>{displayName(r.referrer)}</td>
                    <td>{r.referee_points.toLocaleString()} pts</td>
                    <td>{fmtDate(r.qualified_at)}</td>
                    <td style={{ textAlign: 'right' }}>
                      <button
                        type="button"
                        className="btn btn-primary btn-sm"
                        disabled={awardingId === r.id}
                        onClick={() => handleAwardReferee(r)}
                      >
                        {awardingId === r.id ? (
                          <Loader size={14} className="spin" />
                        ) : (
                          <BadgeCheck size={14} />
                        )}
                        {awardingId === r.id
                          ? 'Awarding...'
                          : `Award ${r.referee_points.toLocaleString()} pts`}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="card" style={{ marginTop: '1.25rem' }}>
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            marginBottom: '0.75rem',
          }}
        >
          <h2 style={{ fontSize: '1rem', fontWeight: 600 }}>
            Recent Referrals
          </h2>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={fetchAll}
          >
            <RotateCcw size={14} /> Refresh
          </button>
        </div>
        {errorMsg && (
          <p style={{ color: 'hsl(0 70% 55%)', fontSize: '0.8rem' }}>
            {errorMsg}
          </p>
        )}
        {recent.length === 0 ? (
          <p
            style={{
              fontSize: '0.85rem',
              color: 'hsl(var(--text-tertiary))',
              padding: '1rem 0',
            }}
          >
            No referrals yet.
          </p>
        ) : (
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Referrer</th>
                  <th>Referred User</th>
                  <th>Code</th>
                  <th>Status</th>
                  <th>Points</th>
                  <th>Referee</th>
                  <th>Joined</th>
                  <th>Qualified</th>
                </tr>
              </thead>
              <tbody>
                {recent.map((r) => (
                  <tr key={r.id}>
                    <td>{displayName(r.referrer)}</td>
                    <td>{displayName(r.referred)}</td>
                    <td>
                      <code>{r.code_used}</code>
                    </td>
                    <td>
                      <span
                        className={`badge ${
                          r.status === 'qualified'
                            ? 'badge-success'
                            : 'badge-warning'
                        }`}
                      >
                        {r.status === 'qualified' ? 'Completed' : 'Pending'}
                      </span>
                    </td>
                    <td>{r.points_awarded.toLocaleString()}</td>
                    <td>
                      {r.referee_awarded_at != null ? (
                        <span className="badge badge-success">
                          {r.referee_points.toLocaleString()} awarded
                        </span>
                      ) : r.status === 'qualified' && r.referee_points > 0 ? (
                        <span className="badge badge-warning">Pending</span>
                      ) : (
                        '—'
                      )}
                    </td>
                    <td>{fmtDate(r.created_at)}</td>
                    <td>{fmtDate(r.qualified_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {AlertComponent}
      {ConfirmComponent}
    </div>
  );
};
