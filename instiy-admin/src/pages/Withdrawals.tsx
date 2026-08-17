import React, { useEffect, useState } from 'react';
import { Link } from "react-router-dom";
import { Percent } from "lucide-react";
import { Search, Filter, Landmark, Clock, Check, X, AlertTriangle, Eye, Loader, Copy } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogDescription } from '../components/dialog';
import { useAlert } from '../components/use-alert';
import { supabase } from '../supabaseClient';
import { formatCurrency, formatGhs } from "../utils/format";

const CopyButton: React.FC<{ text: string }> = ({ text }) => {
  const [copied, setCopied] = useState(false);
  const handleCopy = () => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };
  return (
    <button 
      onClick={handleCopy} 
      style={{ 
        background: 'none', 
        border: 'none', 
        cursor: 'pointer', 
        padding: '2px', 
        display: 'inline-flex', 
        alignItems: 'center', 
        color: copied ? 'hsl(var(--success))' : 'hsl(var(--text-tertiary))',
        marginLeft: '6px'
      }}
      title="Copy to clipboard"
    >
      {copied ? <Check size={12} style={{ color: '#22c55e' }} /> : <Copy size={12} />}
    </button>
  );
};

const extractAccountNumber = (details: string) => {
  if (!details) return '';
  const parts = details.split(' - ');
  if (parts.length > 1) {
    return parts[parts.length - 1].trim();
  }
  return details.trim();
};

const normalizePhoneNumber = (phone: string) => {
  var cleaned = phone.replace(/[^\d+]/g, '');
  if (cleaned.startsWith('0')) {
    cleaned = '+233' + cleaned.substring(1);
  } else if (cleaned.length > 0 && !cleaned.startsWith('+')) {
    cleaned = '+' + cleaned;
  }
  return cleaned;
};

export const Withdrawals: React.FC = () => {
  const [requests, setRequests] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedStatus, setSelectedStatus] = useState('');
  const [selectedRequest, setSelectedRequest] = useState<any>(null);
  const [adminNotes, setAdminNotes] = useState('');
  const [submittingAction, setSubmittingAction] = useState(false);
  const { showAlert, AlertComponent } = useAlert();

  const fetchRequests = async () => {
    try {
      setLoading(true);
      let query = supabase.from('withdrawal_requests')
        .select(`*, users:user_id ( full_name, email, phone_number )`)
        .order('created_at', { ascending: false });

      if (searchQuery.trim()) query = query.or(`users.full_name.ilike.%${searchQuery}%,users.email.ilike.%${searchQuery}%`);
      if (selectedStatus) query = query.eq('status', selectedStatus);

      const { data, error } = await query;
      if (error) throw error;
      setRequests(data || []);
    } catch (error) { console.error('Error:', error); }
    finally { setLoading(false); }
  };

  useEffect(() => { fetchRequests(); }, [searchQuery, selectedStatus]);

  const openModerationModal = (req: any) => { setSelectedRequest(req); setAdminNotes(req.admin_notes || ''); };

  const sendEmailNotification = async (email: string, name: string, amount: number, status: 'completed' | 'failed', reason?: string) => {
    try {
      const subject = `Withdrawal of GH\u20B5 ${formatCurrency(amount)} ${status === 'completed' ? 'processed' : 'rejected'}`;
      const headerColor = status === 'completed' ? 'linear-gradient(135deg, #4D7C59, #059669)' : 'linear-gradient(135deg, #EF4444, #DC2626)';
      const amountColor = status === 'completed' ? '#4D7C59' : '#EF4444';
      const statusTitle = status === 'completed' ? 'Withdrawal Processed' : 'Withdrawal Rejected';

      const bodyHtml = `
<!DOCTYPE html>
<html>
<head>
  <title>${subject}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: ${headerColor}; padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .amount { font-size: 28px; font-weight: 700; color: ${amountColor}; text-align: center; margin: 20px 0; }
    .reason-box { background: #FEF2F2; border: 1px solid #FEE2E2; border-radius: 8px; padding: 12px 16px; margin: 12px 0; color: #991B1B; font-size: 14px; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>${statusTitle}</h1>
    </div>
    <div class="body">
      <p>Hi ${name},</p>
      <p>Your withdrawal request of <strong>GH\u20B5 ${formatCurrency(amount)}</strong> has been ${status === 'completed' ? 'processed successfully.' : 'rejected.'}</p>
      <div class="amount">GH\u20B5 ${formatCurrency(amount)}</div>
      ${status === 'completed'
        ? `<p style="color: #78716c; font-size: 13px; text-align: center;">The funds have been sent to your account.</p>`
        : `<div class="reason-box"><strong>Reason for rejection:</strong> ${reason || 'No reason provided'}</div>
           <p style="color: #78716c; font-size: 13px;">The funds have been returned to your wallet balance. Please review the reason above and try again or contact support if you have any questions.</p>`
      }
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>`;

      await supabase.functions.invoke('send-email', {
        body: { to: email, subject, html: bodyHtml }
      });
    } catch (e) {
      console.error('Failed to send email notification:', e);
    }
  };

  const sendSmsNotification = async (phone: string, name: string, amount: number, status: 'completed' | 'failed', reason?: string) => {
    try {
      const normalizedPhone = normalizePhoneNumber(phone);
      if (!normalizedPhone) return;

      const content = status === 'completed'
        ? `Hi ${name}, your withdrawal request of GHS ${formatCurrency(amount)} has been processed successfully. The funds have been sent to your account. Thank you for using Instiy!`
        : `Hi ${name}, your withdrawal request of GHS ${formatCurrency(amount)} has been rejected. Reason: ${reason || 'No reason provided'}. The funds have been returned to your wallet balance.`;

      await supabase.functions.invoke('send-sms', {
        body: { to: normalizedPhone, content }
      });
    } catch (e) {
      console.error('Failed to send SMS notification:', e);
    }
  };

  const handleProcessRequest = async (targetStatus: string) => {
    if (!selectedRequest) return;
    setSubmittingAction(true);
    try {
      const { error } = await supabase.rpc('process_withdrawal_request', {
        p_request_id: selectedRequest.id, p_status: targetStatus, p_admin_notes: adminNotes.trim() || null
      });
      if (error) throw error;

      // Trigger notifications if completed or failed
      if (targetStatus === 'completed' || targetStatus === 'failed') {
        const userEmail = selectedRequest.users?.email;
        const userName = selectedRequest.users?.full_name || 'Seller';
        const userPhone = selectedRequest.users?.phone_number;
        const amount = Number(selectedRequest.amount_requested);

        if (userEmail) {
          await sendEmailNotification(userEmail, userName, amount, targetStatus, adminNotes.trim());
        }
        if (userPhone) {
          await sendSmsNotification(userPhone, userName, amount, targetStatus, adminNotes.trim());
        }

        // Insert in-app notification into notifications table
        try {
          const title = targetStatus === 'completed' ? 'Withdrawal Completed' : 'Withdrawal Rejected';
          const bodyText = targetStatus === 'completed'
            ? `Your withdrawal request of {formatGhs(amount)} has been processed successfully.`
            : `Your withdrawal request of {formatGhs(amount)} was rejected. Reason: ${adminNotes.trim() || 'No reason provided'}`;

          await supabase.from('notifications').insert({
            user_id: selectedRequest.user_id,
            title: title,
            body: bodyText,
            type: 'withdrawal',
            data: {
              withdrawal_id: selectedRequest.id,
              status: targetStatus,
              amount: amount,
              reason: adminNotes.trim() || null
            }
          });
        } catch (e) {
          console.error('Failed to create in-app notification:', e);
        }
      }

      showAlert('Success', `Withdrawal marked as ${targetStatus.toUpperCase()}!`, 'success');
      setRequests(requests.map(r => r.id === selectedRequest.id ? { ...r, status: targetStatus, admin_notes: adminNotes.trim() } : r));
      setSelectedRequest(null);
    } catch (error) { showAlert('Error', 'Error: ' + (error as any).message, 'error'); }
    finally { setSubmittingAction(false); }
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Cashouts</h1>
              <Link to="/withdrawal-fees" className="btn btn-secondary btn-sm" style={{marginLeft: '0.5rem'}}><Percent size={12} /> Settings</Link>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Review withdrawal requests and approve payouts</p>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '220px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
              placeholder="Search by seller name or email..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
            <Filter size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
            <select className="form-control" style={{ width: '150px', padding: '0.45rem' }} value={selectedStatus} onChange={(e) => setSelectedStatus(e.target.value)}>
              <option value="">All Statuses</option>
              <option value="pending">Pending</option>
              <option value="processing">Processing</option>
              <option value="completed">Completed</option>
              <option value="failed">Failed</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Seller</th>
                <th>Amount</th>
                <th>Fee</th>
                <th>Payout</th>
                <th>Method</th>
                <th>Details</th>
                <th>Status</th>
                <th>Date</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {requests.length === 0 ? (
                <tr><td colSpan={9} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))', padding: '2rem' }}>No withdrawal requests</td></tr>
              ) : (
                requests.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <div style={{ fontWeight: 600, fontSize: '0.82rem' }}>{r.users?.full_name || 'Unknown'}</div>
                      <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>{r.users?.email}</div>
                    </td>
                    <td style={{ fontWeight: 600, fontSize: '0.82rem' }}>{formatGhs(r.amount_requested)}</td>
                    <td style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.82rem' }}>{r.fee_amount ? formatGhs(r.fee_amount) : 'GH₵ 0.00'}</td>
                    <td style={{ fontWeight: 700, fontSize: '0.85rem' }}>{formatGhs(r.amount_to_receive || r.amount_requested)}</td>
                    <td><span className="badge badge-info" style={{ textTransform: 'capitalize' }}>{r.method_type.replace('_', ' ')}</span></td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', fontSize: '0.78rem', maxWidth: '180px' }} title={r.account_details}>
                        <span style={{ color: 'hsl(var(--text-tertiary))', marginRight: '4px' }}>{r.provider_type ? `(${r.provider_type})` : ''}</span>
                        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1 }}>{r.account_details}</span>
                        <CopyButton text={extractAccountNumber(r.account_details)} />
                      </div>
                    </td>
                    <td>
                      <span className={`badge ${r.status === 'completed' ? 'badge-success' : r.status === 'pending' ? 'badge-warning' : r.status === 'processing' ? 'badge-info' : 'badge-danger'}`}>
                        {r.status}
                      </span>
                    </td>
                    <td style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.78rem' }}>{new Date(r.created_at).toLocaleDateString()}</td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openModerationModal(r)}><Eye size={13} /> Review</button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Moderation Modal */}
      <Dialog open={!!selectedRequest} onOpenChange={(open) => !open && setSelectedRequest(null)}>
        <DialogContent style={{ maxWidth: '480px' }}>
          <DialogHeader>
            <DialogTitle style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Landmark size={18} style={{ color: 'hsl(var(--accent))' }} /> Review Cashout
            </DialogTitle>
            <DialogDescription>
              Review and process the withdrawal request for {selectedRequest?.users?.full_name || 'this seller'}.
            </DialogDescription>
          </DialogHeader>

          <div className="card" style={{ background: 'hsl(var(--bg-surface))', display: 'flex', flexDirection: 'column', gap: '0.375rem', marginBottom: '1rem' }}>
            {[
              ['Seller', selectedRequest?.users?.full_name],
              ['Email', selectedRequest?.users?.email],
              ['Method', <span style={{ textTransform: 'uppercase', fontWeight: 600 }}>{selectedRequest?.method_type?.replace('_', ' ')}</span>],
              ...(selectedRequest?.provider_type ? [['Provider', selectedRequest.provider_type]] : []),
            ].map(([label, value], i) => (
              <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                <span style={{ color: 'hsl(var(--text-tertiary))' }}>{label}:</span>
                <span>{value}</span>
              </div>
            ))}
            <div style={{ borderTop: '1px solid hsl(var(--border))', paddingTop: '0.375rem', marginTop: '0.25rem' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.25rem' }}>
                <span style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.78rem' }}>Account Details:</span>
                <CopyButton text={extractAccountNumber(selectedRequest?.account_details || '')} />
              </div>
              <div style={{ background: 'hsl(var(--bg-card))', padding: '0.5rem', borderRadius: '4px', border: '1px solid hsl(var(--border))', fontFamily: 'monospace', fontSize: '0.78rem', whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>
                {selectedRequest?.account_details}
              </div>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem', borderTop: '1px solid hsl(var(--border))', paddingTop: '0.375rem', marginTop: '0.25rem' }}>
              <span style={{ color: 'hsl(var(--text-tertiary))' }}>Payout:</span>
              <span style={{ fontWeight: 700 }}>{formatGhs(selectedRequest?.amount_to_receive || selectedRequest?.amount_requested || 0)}</span>
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">Admin Notes / Transaction Ref</label>
            <textarea className="form-control" style={{ minHeight: '70px', resize: 'vertical' }}
              placeholder="Transaction ID, reference, or reason..." value={adminNotes} onChange={(e) => setAdminNotes(e.target.value)} />
          </div>

          <DialogFooter>
            {selectedRequest?.status === 'pending' || selectedRequest?.status === 'processing' ? (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', width: '100%' }}>
                {selectedRequest?.status === 'pending' && (
                  <button className="btn btn-secondary" style={{ width: '100%' }} onClick={() => handleProcessRequest('processing')} disabled={submittingAction}>
                    <Clock size={14} /> Mark Processing
                  </button>
                )}
                <div style={{ display: 'flex', gap: '0.625rem' }}>
                  <button className="btn btn-danger" style={{ flex: 1 }} onClick={() => handleProcessRequest('failed')} disabled={submittingAction}>
                    <X size={14} /> Reject
                  </button>
                  <button className="btn btn-success" style={{ flex: 1 }} onClick={() => handleProcessRequest('completed')} disabled={submittingAction}>
                    <Check size={14} /> Complete
                  </button>
                </div>
              </div>
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'hsl(var(--danger-dim))', border: '1px solid hsl(var(--danger) / 0.2)', padding: '0.625rem', borderRadius: 'var(--radius-sm)', color: 'hsl(var(--text-secondary))', fontSize: '0.82rem', width: '100%' }}>
                <AlertTriangle size={16} style={{ color: 'hsl(var(--danger-hover))', flexShrink: 0 }} />
                Already marked as <strong style={{ textTransform: 'capitalize' }}>{selectedRequest?.status}</strong>.
              </div>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {AlertComponent}
    </div>
  );
};
