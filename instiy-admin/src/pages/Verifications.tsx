import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import {
  Shield, Eye, Loader, CheckCircle, XCircle, Ban,
  Clock, AlertTriangle
} from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogFooter, DialogTitle, DialogDescription } from '../components/dialog';
import { useAlert } from '../components/use-alert';

type VerificationStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'revoked' | '';

const STATUS_TABS: { label: string; value: VerificationStatus }[] = [
  { label: 'All', value: '' },
  { label: 'Pending', value: 'pending' },
  { label: 'Approved', value: 'approved' },
  { label: 'Rejected', value: 'rejected' },
  { label: 'Revoked', value: 'revoked' },
];

export const Verifications: React.FC = () => {
  const { alert, AlertComponent } = useAlert();
  const [verifications, setVerifications] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<VerificationStatus>('');
  const [selectedVerification, setSelectedVerification] = useState<any>(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [adminNotes, setAdminNotes] = useState('');
  const [showNotesModal, setShowNotesModal] = useState<{ type: 'approve' | 'reject' | 'revoke'; id: string } | null>(null);

  const fetchVerifications = async () => {
    try {
      setLoading(true);
      setFetchError(null);
      let query = supabase
        .from('seller_verifications')
        .select('*, users:user_id(id, full_name, email, avatar_url, university, is_verified)')
        .order('created_at', { ascending: false });

      if (activeTab) {
        query = query.eq('status', activeTab);
      }

      const { data, error } = await query;
      if (error) {
        console.error('Supabase error:', error);
        throw error;
      }
      setVerifications(data || []);
    } catch (error: any) {
      console.error('Error fetching verifications:', error);
      setFetchError(error?.message || 'Failed to load verifications');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchVerifications(); }, [activeTab]);

  const handleApprove = async (id: string) => {
    try {
      setActionLoading(true);
      const { data, error } = await supabase.rpc('approve_seller_verification', {
        p_verification_id: id,
        p_admin_id: (await supabase.auth.getUser()).data.user?.id,
        p_notes: adminNotes || null,
      });
      if (error) throw error;
      if (data?.success === false) {
        alert(data.error, { variant: 'danger' });
        return;
      }
      // Optimistic update: instantly reflect the new status in the list
      setVerifications((prev) =>
        prev.map((v) =>
          v.id === id ? { ...v, status: 'approved', admin_notes: adminNotes || v.admin_notes } : v
        )
      );
      setSelectedVerification((prev: any) =>
        prev?.id === id ? { ...prev, status: 'approved', admin_notes: adminNotes || prev.admin_notes } : null
      );
      setShowNotesModal(null);
      setAdminNotes('');
      // Refetch in background for consistency
      fetchVerifications();
    } catch (error) {
      alert('Error: ' + (error as any).message, { variant: 'danger' });
    } finally {
      setActionLoading(false);
    }
  };

  const handleReject = async (id: string) => {
    try {
      setActionLoading(true);
      const { data, error } = await supabase.rpc('reject_seller_verification', {
        p_verification_id: id,
        p_admin_id: (await supabase.auth.getUser()).data.user?.id,
        p_notes: adminNotes || null,
      });
      if (error) throw error;
      if (data?.success === false) {
        alert(data.error, { variant: 'danger' });
        return;
      }
      // Optimistic update: instantly reflect the new status in the list
      setVerifications((prev) =>
        prev.map((v) =>
          v.id === id ? { ...v, status: 'rejected', admin_notes: adminNotes || v.admin_notes } : v
        )
      );
      setSelectedVerification((prev: any) =>
        prev?.id === id ? { ...prev, status: 'rejected', admin_notes: adminNotes || prev.admin_notes } : null
      );
      setShowNotesModal(null);
      setAdminNotes('');
      // Refetch in background for consistency
      fetchVerifications();
    } catch (error) {
      alert('Error: ' + (error as any).message, { variant: 'danger' });
    } finally {
      setActionLoading(false);
    }
  };

  const handleRevoke = async (id: string) => {
    try {
      setActionLoading(true);
      const { data, error } = await supabase.rpc('revoke_seller_verification', {
        p_verification_id: id,
        p_admin_id: (await supabase.auth.getUser()).data.user?.id,
        p_notes: adminNotes || null,
      });
      if (error) throw error;
      if (data?.success === false) {
        alert(data.error, { variant: 'danger' });
        return;
      }
      // Optimistic update: instantly reflect the new status in the list
      setVerifications((prev) =>
        prev.map((v) =>
          v.id === id ? { ...v, status: 'revoked', admin_notes: adminNotes || v.admin_notes } : v
        )
      );
      setSelectedVerification((prev: any) =>
        prev?.id === id ? { ...prev, status: 'revoked', admin_notes: adminNotes || prev.admin_notes } : null
      );
      setShowNotesModal(null);
      setAdminNotes('');
      // Refetch in background for consistency
      fetchVerifications();
    } catch (error) {
      alert('Error: ' + (error as any).message, { variant: 'danger' });
    } finally {
      setActionLoading(false);
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'pending':
        return <span className="badge badge-warning"><Clock size={10} style={{ marginRight: 4 }} /> Pending</span>;
      case 'approved':
        return <span className="badge badge-success"><CheckCircle size={10} style={{ marginRight: 4 }} /> Approved</span>;
      case 'rejected':
        return <span className="badge badge-danger"><XCircle size={10} style={{ marginRight: 4 }} /> Rejected</span>;
      case 'cancelled':
        return <span className="badge badge-info"><Ban size={10} style={{ marginRight: 4 }} /> Cancelled</span>;
      case 'revoked':
        return <span className="badge badge-danger"><Ban size={10} style={{ marginRight: 4 }} /> Revoked</span>;
      default:
        return <span className="badge">{status}</span>;
    }
  };


  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Seller Verifications</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>
            Review and manage seller verification requests
          </p>
        </div>
      </div>

      {/* Status Tabs */}
      <div className="card" style={{ marginBottom: '1.5rem', padding: '0.5rem' }}>
        <div style={{ display: 'flex', gap: '0.25rem', flexWrap: 'wrap' }}>
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.value}
              className={`btn btn-sm ${activeTab === tab.value ? 'btn-primary' : 'btn-secondary'}`}
              onClick={() => setActiveTab(tab.value)}
            >
              {tab.label}
              {tab.value === '' && (
                <span style={{ marginLeft: 4, opacity: 0.7 }}>({verifications.length})</span>
              )}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : fetchError ? (
        <div className="card" style={{ textAlign: 'center', padding: '3rem' }}>
          <AlertTriangle size={48} style={{ color: 'hsl(var(--danger-hover))', margin: '0 auto 1rem' }} />
          <p style={{ color: 'hsl(var(--danger-hover))', fontWeight: 600, marginBottom: '0.5rem' }}>Failed to load verifications</p>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginBottom: '1rem' }}>{fetchError}</p>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>
            Make sure the migration has been applied. Run the SQL in your Supabase Dashboard → SQL Editor.
          </p>
          <button className="btn btn-primary" style={{ marginTop: '1rem' }} onClick={fetchVerifications}>
            Retry
          </button>
        </div>
      ) : verifications.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '3rem' }}>
          <Shield size={48} style={{ color: 'hsl(var(--text-tertiary))', margin: '0 auto 1rem' }} />
          <p style={{ color: 'hsl(var(--text-tertiary))' }}>No verification requests found</p>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem', marginTop: '0.5rem' }}>
            If sellers have submitted verifications, make sure the migration SQL has been applied in Supabase Dashboard → SQL Editor.
          </p>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Seller</th>
                <th>University</th>
                <th>Submitted</th>
                <th>Status</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {verifications.map((v) => {
                const user = v.users;
                return (
                  <tr key={v.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <img
                          src={user?.avatar_url || 'https://api.dicebear.com/7.x/bottts/svg?seed=' + user?.email}
                          alt={user?.full_name}
                          style={{ width: '34px', height: '34px', borderRadius: '50%', border: '1px solid hsl(var(--border))', objectFit: 'cover' }}
                        />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{user?.full_name}</div>
                          <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>{user?.email}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ fontSize: '0.85rem' }}>{user?.university || 'N/A'}</td>
                    <td style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>
                      {new Date(v.created_at).toLocaleDateString()}
                    </td>
                    <td>{getStatusBadge(v.status)}</td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => setSelectedVerification(v)}>
                          <Eye size={13} /> Review
                        </button>
                        {v.status === 'pending' && (
                          <>
                            <button className="btn btn-success btn-sm" onClick={() => setShowNotesModal({ type: 'approve', id: v.id })}>
                              <CheckCircle size={13} /> Approve
                            </button>
                            <button className="btn btn-danger btn-sm" onClick={() => setShowNotesModal({ type: 'reject', id: v.id })}>
                              <XCircle size={13} /> Reject
                            </button>
                          </>
                        )}
                        {v.status === 'approved' && (
                          <button className="btn btn-danger btn-sm" onClick={() => setShowNotesModal({ type: 'revoke', id: v.id })}>
                            <Ban size={13} /> Revoke
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Detail Modal */}
      <Dialog open={!!selectedVerification} onOpenChange={(open) => !open && setSelectedVerification(null)}>
        <DialogContent style={{ maxWidth: '600px' }}>
          <DialogHeader>
            <DialogTitle>Verification Details</DialogTitle>
            <DialogDescription>Review the seller's verification submission.</DialogDescription>
          </DialogHeader>

          {selectedVerification && (
            <>
              {/* Seller Info */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', padding: '0.75rem 0' }}>
                <img
                  src={selectedVerification.users?.avatar_url || 'https://api.dicebear.com/7.x/bottts/svg?seed=' + selectedVerification.users?.email}
                  alt=""
                  style={{ width: '56px', height: '56px', borderRadius: '50%', border: '2px solid hsl(var(--accent))', objectFit: 'cover' }}
                />
                <div>
                  <h3 style={{ fontSize: '1rem' }}>{selectedVerification.users?.full_name}</h3>
                  <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>{selectedVerification.users?.email}</p>
                  <div style={{ marginTop: '0.25rem' }}>{getStatusBadge(selectedVerification.status)}</div>
                </div>
              </div>

              {/* Student Info */}
              <div className="card" style={{ background: 'hsl(var(--bg-surface))' }}>
                <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600, marginBottom: '0.75rem' }}>
                  Student Information
                </h4>
                {[
                  ['Date of Birth', new Date(selectedVerification.date_of_birth).toLocaleDateString()],
                  ['Year of Entrance', selectedVerification.year_of_entrance],
                  ['Graduation Year', selectedVerification.graduation_year],
                  ['Residential Address', selectedVerification.residential_address],
                  ['Digital Address', selectedVerification.digital_address || 'N/A'],
                  ['Submitted', new Date(selectedVerification.created_at).toLocaleString()],
                ].map(([label, value]) => (
                  <div key={label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem', padding: '0.25rem 0' }}>
                    <span style={{ color: 'hsl(var(--text-tertiary))' }}>{label}:</span>
                    <span style={{ fontWeight: 500 }}>{String(value)}</span>
                  </div>
                ))}
              </div>

              {/* Documents */}
              <div className="card">
                <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600, marginBottom: '0.75rem' }}>
                  Documents
                </h4>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                  {/* Student ID Front */}
                  <div>
                    <p style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.375rem' }}>Student ID (Front)</p>
                    <a href={selectedVerification.student_id_front_url} target="_blank" rel="noopener noreferrer">
                      <img
                        src={selectedVerification.student_id_front_url}
                        alt="Student ID Front"
                        style={{ width: '100%', maxHeight: '200px', objectFit: 'contain', borderRadius: '8px', border: '1px solid hsl(var(--border))', background: 'hsl(var(--bg-surface))' }}
                      />
                    </a>
                  </div>
                  {/* Student ID Back */}
                  <div>
                    <p style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.375rem' }}>Student ID (Back)</p>
                    <a href={selectedVerification.student_id_back_url} target="_blank" rel="noopener noreferrer">
                      <img
                        src={selectedVerification.student_id_back_url}
                        alt="Student ID Back"
                        style={{ width: '100%', maxHeight: '200px', objectFit: 'contain', borderRadius: '8px', border: '1px solid hsl(var(--border))', background: 'hsl(var(--bg-surface))' }}
                      />
                    </a>
                  </div>
                  {/* Live Video */}
                  <div>
                    <p style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.375rem' }}>Live Verification Video</p>
                    <video
                      src={selectedVerification.live_video_url}
                      controls
                      style={{ width: '100%', maxHeight: '300px', borderRadius: '8px', border: '1px solid hsl(var(--border))', background: 'black' }}
                    />
                  </div>
                </div>
              </div>

              {/* Admin Notes */}
              {selectedVerification.admin_notes && (
                <div className="card" style={{ background: 'hsl(var(--warning-dim))' }}>
                  <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600, marginBottom: '0.375rem' }}>
                    Admin Notes
                  </h4>
                  <p style={{ fontSize: '0.85rem' }}>{selectedVerification.admin_notes}</p>
                </div>
              )}

              {/* Actions */}
              {selectedVerification.status === 'pending' && (
                <DialogFooter style={{ flexDirection: 'column', gap: '0.625rem' }}>
                  <div className="form-group">
                    <label className="form-label">Admin Notes (optional)</label>
                    <textarea
                      className="form-control"
                      rows={2}
                      placeholder="Add notes about this verification..."
                      value={adminNotes}
                      onChange={(e) => setAdminNotes(e.target.value)}
                    />
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.625rem' }}>
                    <button
                      className="btn btn-success"
                      onClick={() => handleApprove(selectedVerification.id)}
                      disabled={actionLoading}
                    >
                      {actionLoading ? <Loader className="spin" size={14} /> : <CheckCircle size={14} />}
                      Approve
                    </button>
                    <button
                      className="btn btn-danger"
                      onClick={() => handleReject(selectedVerification.id)}
                      disabled={actionLoading}
                    >
                      {actionLoading ? <Loader className="spin" size={14} /> : <XCircle size={14} />}
                      Reject
                    </button>
                  </div>
                </DialogFooter>
              )}

              {selectedVerification.status === 'approved' && (
                <DialogFooter style={{ flexDirection: 'column', gap: '0.625rem' }}>
                  <div className="form-group">
                    <label className="form-label">Revoke Notes (optional)</label>
                    <textarea
                      className="form-control"
                      rows={2}
                      placeholder="Reason for revoking verification..."
                      value={adminNotes}
                      onChange={(e) => setAdminNotes(e.target.value)}
                    />
                  </div>
                  <button
                    className="btn btn-danger"
                    style={{ width: '100%' }}
                    onClick={() => handleRevoke(selectedVerification.id)}
                    disabled={actionLoading}
                  >
                    {actionLoading ? <Loader className="spin" size={14} /> : <Ban size={14} />}
                    Revoke Verification
                  </button>
                </DialogFooter>
              )}
            </>
          )}
        </DialogContent>
      </Dialog>

      {/* Notes Modal for quick approve/reject from table */}
      <Dialog open={!!showNotesModal} onOpenChange={(open) => { if (!open) { setShowNotesModal(null); setAdminNotes(''); } }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {showNotesModal?.type === 'approve' ? 'Approve Verification' :
               showNotesModal?.type === 'reject' ? 'Reject Verification' : 'Revoke Verification'}
            </DialogTitle>
            <DialogDescription>Add optional notes for this action.</DialogDescription>
          </DialogHeader>
          <div className="form-group">
            <label className="form-label">Notes (optional)</label>
            <textarea
              className="form-control"
              rows={3}
              placeholder="Add any notes..."
              value={adminNotes}
              onChange={(e) => setAdminNotes(e.target.value)}
            />
          </div>
          <DialogFooter>
            <button className="btn btn-secondary" onClick={() => { setShowNotesModal(null); setAdminNotes(''); }}>
              Cancel
            </button>
            <button
              className={`btn ${showNotesModal?.type === 'approve' ? 'btn-success' : 'btn-danger'}`}
              onClick={() => {
                if (showNotesModal?.type === 'approve') handleApprove(showNotesModal.id);
                else if (showNotesModal?.type === 'reject') handleReject(showNotesModal.id);
                else if (showNotesModal?.type === 'revoke') handleRevoke(showNotesModal.id);
              }}
              disabled={actionLoading}
            >
              {actionLoading ? <Loader className="spin" size={14} /> : null}
              {showNotesModal?.type === 'approve' ? 'Approve' :
               showNotesModal?.type === 'reject' ? 'Reject' : 'Revoke'}
            </button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
      {AlertComponent}
    </div>
  );
};
