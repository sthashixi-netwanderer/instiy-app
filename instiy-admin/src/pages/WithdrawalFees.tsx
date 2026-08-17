import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Percent, Save, Loader, Check, RotateCcw } from 'lucide-react';
import { formatCurrency } from "../utils/format";

export const WithdrawalFees: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  const [mobileMoneyRate, setMobileMoneyRate] = useState(2);
  const [bankRate, setBankRate] = useState(1);

  useEffect(() => {
    fetchFees();
  }, []);

  const fetchFees = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('platform_settings')
        .select('value')
        .eq('key', 'withdrawal_fees')
        .maybeSingle();

      if (error) throw error;

      if (data?.value) {
        const v = data.value as Record<string, number>;
        if (v.mobile_money != null) setMobileMoneyRate(v.mobile_money * 100);
        if (v.bank != null) setBankRate(v.bank * 100);
      }
    } catch (err) {
      console.error('Error fetching withdrawal fees:', err);
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
        .from('platform_settings')
        .upsert(
          {
            key: 'withdrawal_fees',
            value: {
              mobile_money: mobileMoneyRate / 100,
              bank: bankRate / 100,
            },
          },
          { onConflict: 'key' }
        );

      if (error) throw error;
      setSaved(true);
      setTimeout(() => setSaved(false), 3000);
    } catch (err) {
      console.error('Error saving withdrawal fees:', err);
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    setMobileMoneyRate(2);
    setBankRate(1);
  };

  if (loading) {
    return (
      <div className="page-loading">
        <Loader size={24} className="spin" />
        <span>Loading fee settings...</span>
      </div>
    );
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h1>Withdrawal Fees</h1>
          <p className="page-subtitle">
            Configure platform fee rates for seller withdrawals
          </p>
        </div>
      </div>

      <form onSubmit={handleSave} className="settings-card">
        <div className="settings-card-header">
          <Percent size={20} />
          <h2>Fee Rates</h2>
        </div>

        <div className="form-group">
          <label>Mobile Money Fee (%)</label>
          <div className="input-with-suffix">
            <input
              type="number"
              step="0.1"
              min="0"
              max="50"
              value={mobileMoneyRate}
              onChange={(e) => setMobileMoneyRate(parseFloat(e.target.value) || 0)}
              className="form-control"
            />
            <span className="input-suffix">%</span>
          </div>
          <p className="form-hint">
            Current: {mobileMoneyRate}% — On a GHS 100 withdrawal, seller pays GHS {formatCurrency(mobileMoneyRate)} fee
          </p>
        </div>

        <div className="form-group">
          <label>Bank Transfer Fee (%)</label>
          <div className="input-with-suffix">
            <input
              type="number"
              step="0.1"
              min="0"
              max="50"
              value={bankRate}
              onChange={(e) => setBankRate(parseFloat(e.target.value) || 0)}
              className="form-control"
            />
            <span className="input-suffix">%</span>
          </div>
          <p className="form-hint">
            Current: {bankRate}% — On a GHS 100 withdrawal, seller pays GHS {formatCurrency(bankRate)} fee
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
    </div>
  );
};
