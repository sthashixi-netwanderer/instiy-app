import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Search, Shield, UserCheck, X, Eye, Loader, CreditCard, ArrowUpRight, ArrowDownLeft, Trash2 } from 'lucide-react';

export const Users: React.FC = () => {
  const [users, setUsers] = useState<any[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [loading, setLoading] = useState(true);
  const [selectedUser, setSelectedUser] = useState<any>(null);
  const [userWallet, setUserWallet] = useState<any>(null);
  const [userTransactions, setUserTransactions] = useState<any[]>([]);
  const [loadingWallet, setLoadingWallet] = useState(false);
  const [listedCount, setListedCount] = useState<number | null>(null);
  const [ordersCount, setOrdersCount] = useState<number | null>(null);
  const [loadingStats, setLoadingStats] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [deleteConfirmName, setDeleteConfirmName] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      let query = supabase.from('users').select('*').order('created_at', { ascending: false });
      if (searchQuery.trim() !== '') {
        query = query.or(`email.ilike.%${searchQuery}%,full_name.ilike.%${searchQuery}%,university.ilike.%${searchQuery}%`);
      }
      const { data, error } = await query;
      if (error) throw error;
      setUsers(data || []);
    } catch (error) {
      console.error('Error fetching users:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchUsers(); }, [searchQuery]);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      setCurrentUserId(data.user?.id ?? null);
    });
  }, []);

  const openDeleteModal = () => {
    setDeleteConfirmName('');
    setShowDeleteModal(true);
  };

  const deleteUser = async () => {
    if (!selectedUser || deleteConfirmName.trim() !== selectedUser.full_name) return;
    setDeleting(true);
    try {
      const { data, error } = await supabase.functions.invoke('delete-user', {
        body: { user_id: selectedUser.id },
      });
      if (error) throw error;
      if (data?.error) throw new Error(data.error);

      setUsers(users.filter(u => u.id !== selectedUser.id));
      setSelectedUser(null);
      setShowDeleteModal(false);
    } catch (error) {
      alert('Error deleting user: ' + (error as any).message);
    } finally {
      setDeleting(false);
    }
  };

  const viewUserDetails = async (user: any) => {
    setSelectedUser(user);
    setLoadingWallet(true);
    setLoadingStats(true);
    setUserWallet(null);
    setUserTransactions([]);
    setListedCount(null);
    setOrdersCount(null);

    try {
      const { data: wallet } = await supabase
        .from('wallets').select('*').eq('user_id', user.id).maybeSingle();

      if (wallet) {
        setUserWallet(wallet);
        const { data: txs } = await supabase
          .from('wallet_transactions').select('*')
          .eq('wallet_id', wallet.id).order('created_at', { ascending: false }).limit(10);
        setUserTransactions(txs || []);
      }

      const { count: pCount } = await supabase
        .from('products').select('*', { count: 'exact', head: true }).eq('seller_id', user.id);
      setListedCount(pCount || 0);

      const { count: oCount } = await supabase
        .from('orders').select('*', { count: 'exact', head: true }).eq('buyer_id', user.id);
      setOrdersCount(oCount || 0);
    } catch (error) {
      console.error('Error fetching user details:', error);
    } finally {
      setLoadingWallet(false);
      setLoadingStats(false);
    }
  };

  const toggleVerification = async (userId: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase.from('users').update({ is_verified: !currentStatus }).eq('id', userId);
      if (error) throw error;
      setUsers(users.map(u => u.id === userId ? { ...u, is_verified: !currentStatus } : u));
      if (selectedUser?.id === userId) setSelectedUser({ ...selectedUser, is_verified: !currentStatus });
    } catch (error) {
      alert('Error updating verification: ' + (error as any).message);
    }
  };

  const toggleAdminStatus = async (userId: string, currentStatus: boolean) => {
    const msg = currentStatus
      ? "Remove admin privileges from this user?"
      : "Grant admin privileges? They'll have full database access.";
    if (!window.confirm(msg)) return;

    try {
      const { error } = await supabase.from('users').update({ is_admin: !currentStatus }).eq('id', userId);
      if (error) throw error;
      setUsers(users.map(u => u.id === userId ? { ...u, is_admin: !currentStatus } : u));
      if (selectedUser?.id === userId) setSelectedUser({ ...selectedUser, is_admin: !currentStatus });
    } catch (error) {
      alert('Error updating admin status: ' + (error as any).message);
    }
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Users</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Manage users, verify sellers, and assign roles</p>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '1.5rem', padding: '0.875rem' }}>
        <div style={{ position: 'relative', width: '100%', maxWidth: '360px' }}>
          <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
          <input
            type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
            placeholder="Search by name, email, or university..."
            value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)}
          />
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
                <th>Profile</th>
                <th>University</th>
                <th>Seller Status</th>
                <th>Role</th>
                <th>Joined</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {users.length === 0 ? (
                <tr><td colSpan={6} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))', padding: '2rem' }}>No users found</td></tr>
              ) : (
                users.map((user) => (
                  <tr key={user.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <img
                          src={user.avatar_url || 'https://api.dicebear.com/7.x/bottts/svg?seed=' + user.email}
                          alt={user.full_name}
                          style={{ width: '34px', height: '34px', borderRadius: '50%', border: '1px solid hsl(var(--border))', objectFit: 'cover' }}
                        />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{user.full_name}</div>
                          <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>{user.email}</div>
                        </div>
                      </div>
                    </td>
                    <td style={{ fontSize: '0.85rem' }}>{user.university || 'N/A'}</td>
                    <td>
                      <span className={`badge ${user.is_verified ? 'badge-success' : 'badge-warning'}`}>
                        {user.is_verified ? 'Verified' : 'Standard'}
                      </span>
                    </td>
                    <td>
                      {user.is_admin ? (
                        <span className="badge badge-danger" style={{ display: 'inline-flex', gap: '0.25rem', alignItems: 'center' }}>
                          <Shield size={10} /> Admin
                        </span>
                      ) : (
                        <span className="badge badge-info">User</span>
                      )}
                    </td>
                    <td style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>
                      {new Date(user.created_at).toLocaleDateString()}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => viewUserDetails(user)}>
                          <Eye size={13} /> Details
                        </button>
                        <button
                          className={`btn btn-sm ${user.is_verified ? 'btn-danger' : 'btn-success'}`}
                          onClick={() => toggleVerification(user.id, user.is_verified)}
                        >
                          <UserCheck size={13} /> {user.is_verified ? 'Unverify' : 'Verify'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* User Details Drawer */}
      {selectedUser && (
        <div className="drawer-backdrop" onClick={() => setSelectedUser(null)}>
          <div className="drawer" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.875rem' }}>
              <h2 style={{ fontSize: '1.2rem', fontFamily: 'var(--font-title)' }}>User Profile</h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-secondary))', padding: '4px' }} onClick={() => setSelectedUser(null)}>
                <X size={20} />
              </button>
            </div>

            {/* Profile Overview */}
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.625rem', padding: '0.75rem 0' }}>
              <img
                src={selectedUser.avatar_url || 'https://api.dicebear.com/7.x/bottts/svg?seed=' + selectedUser.email}
                alt={selectedUser.full_name}
                style={{ width: '72px', height: '72px', borderRadius: '50%', border: '2px solid hsl(var(--accent))', objectFit: 'cover' }}
              />
              <h3 style={{ fontSize: '1.1rem' }}>{selectedUser.full_name}</h3>
              <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>{selectedUser.email}</p>
            </div>

            {/* Details */}
            <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem', background: 'hsl(var(--bg-surface))' }}>
              {[
                ['University', selectedUser.university || 'N/A'],
                ['Phone', selectedUser.phone_number || 'N/A'],
                ['Joined', new Date(selectedUser.created_at).toLocaleString()],
              ].map(([label, value]) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                  <span style={{ color: 'hsl(var(--text-tertiary))' }}>{label}:</span>
                  <span>{value}</span>
                </div>
              ))}
              <div style={{ borderTop: '1px solid hsl(var(--border))', paddingTop: '0.5rem', marginTop: '0.25rem', display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                <span style={{ color: 'hsl(var(--text-tertiary))' }}>Listed:</span>
                <span>{loadingStats ? '...' : listedCount}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                <span style={{ color: 'hsl(var(--text-tertiary))' }}>Orders:</span>
                <span>{loadingStats ? '...' : ordersCount}</span>
              </div>
              {selectedUser.bio && (
                <div style={{ borderTop: '1px solid hsl(var(--border))', paddingTop: '0.625rem', marginTop: '0.25rem' }}>
                  <span style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.78rem', display: 'block', marginBottom: '0.25rem' }}>Bio</span>
                  <p style={{ fontSize: '0.82rem', lineHeight: 1.5 }}>{selectedUser.bio}</p>
                </div>
              )}
            </div>

            {/* Wallet */}
            <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
              <h4 style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.9rem', color: 'hsl(var(--text-secondary))', fontWeight: 600 }}>
                <CreditCard size={16} /> Seller Wallet
              </h4>
              {loadingWallet ? (
                <div style={{ display: 'flex', justifyContent: 'center', padding: '1rem' }}>
                  <Loader className="spin" size={18} style={{ color: 'hsl(var(--accent))' }} />
                </div>
              ) : userWallet ? (
                <div>
                  <div style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', margin: '0.25rem 0' }}>
                    GH&#8373;{Number(userWallet.balance).toFixed(2)}
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>
                    <span>Pending: GH&#8373;{Number(userWallet.pending_balance || 0).toFixed(2)}</span>
                    <span>Updated: {new Date(userWallet.updated_at).toLocaleDateString()}</span>
                  </div>

                  <div style={{ marginTop: '1rem' }}>
                    <h5 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.5rem', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Recent Transactions</h5>
                    {userTransactions.length === 0 ? (
                      <p style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textAlign: 'center', padding: '0.5rem' }}>No transactions</p>
                    ) : (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.375rem', maxHeight: '160px', overflowY: 'auto' }}>
                        {userTransactions.map((tx) => {
                          const isIncoming = ['deposit', 'transfer_in', 'refund'].includes(tx.type);
                          return (
                            <div key={tx.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '0.5rem', background: 'hsl(var(--bg-surface))', borderRadius: '4px', fontSize: '0.78rem' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                                {isIncoming ? (
                                  <ArrowDownLeft size={13} style={{ color: 'hsl(var(--success-hover))' }} />
                                ) : (
                                  <ArrowUpRight size={13} style={{ color: 'hsl(var(--danger-hover))' }} />
                                )}
                                <div>
                                  <div style={{ fontWeight: 600, textTransform: 'capitalize' }}>{tx.type.replace('_', ' ')}</div>
                                  <div style={{ fontSize: '0.68rem', color: 'hsl(var(--text-tertiary))' }}>{tx.description || tx.reference || ''}</div>
                                </div>
                              </div>
                              <div style={{ fontWeight: 700, color: isIncoming ? 'hsl(var(--success-hover))' : 'hsl(var(--danger-hover))' }}>
                                {isIncoming ? '+' : '-'}GH&#8373;{Number(tx.amount).toFixed(2)}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                </div>
              ) : (
                <p style={{ fontSize: '0.82rem', color: 'hsl(var(--text-tertiary))', textAlign: 'center', padding: '0.75rem' }}>No wallet found</p>
              )}
            </div>

            {/* Actions */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem', marginTop: 'auto' }}>
              <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600 }}>Admin Controls</h4>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.625rem' }}>
                <button
                  className={`btn ${selectedUser.is_verified ? 'btn-danger' : 'btn-success'}`}
                  onClick={() => toggleVerification(selectedUser.id, selectedUser.is_verified)}
                >
                  {selectedUser.is_verified ? 'Revoke Verification' : 'Verify Seller'}
                </button>
                <button
                  className={`btn ${selectedUser.is_admin ? 'btn-secondary' : 'btn-danger'}`}
                  style={selectedUser.is_admin ? { border: '1px solid hsl(var(--danger) / 0.4)', color: 'hsl(var(--danger-hover))' } : {}}
                  onClick={() => toggleAdminStatus(selectedUser.id, selectedUser.is_admin)}
                >
                  {selectedUser.is_admin ? 'Remove Admin' : 'Grant Admin'}
                </button>
              </div>
              <button
                className="btn btn-danger"
                style={{ marginTop: '0.25rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}
                onClick={openDeleteModal}
                disabled={selectedUser.id === currentUserId}
                title={selectedUser.id === currentUserId ? "Cannot delete your own account" : "Permanently delete this user"}
              >
                <Trash2 size={14} /> Delete User Account
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {showDeleteModal && selectedUser && (
        <div className="modal-backdrop" onClick={() => setShowDeleteModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()} style={{ maxWidth: '420px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
              <h3 style={{ fontSize: '1.1rem', fontFamily: 'var(--font-title)', color: 'hsl(var(--danger-hover))' }}>
                Delete User Account
              </h3>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-secondary))', padding: '4px' }} onClick={() => setShowDeleteModal(false)}>
                <X size={18} />
              </button>
            </div>
            <p style={{ fontSize: '0.85rem', color: 'hsl(var(--text-secondary))', marginBottom: '0.75rem' }}>
              This will permanently delete <strong>{selectedUser.full_name}</strong>'s account and all associated data (products, orders, wallet, messages). This action cannot be undone.
            </p>
            <p style={{ fontSize: '0.82rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.75rem' }}>
              Type <strong>{selectedUser.full_name}</strong> to confirm:
            </p>
            <input
              type="text"
              className="form-control"
              value={deleteConfirmName}
              onChange={(e) => setDeleteConfirmName(e.target.value)}
              placeholder="Enter full name"
              style={{ marginBottom: '1rem' }}
              autoFocus
            />
            <div style={{ display: 'flex', gap: '0.625rem', justifyContent: 'flex-end' }}>
              <button className="btn btn-secondary" onClick={() => setShowDeleteModal(false)}>Cancel</button>
              <button
                className="btn btn-danger"
                onClick={deleteUser}
                disabled={deleteConfirmName.trim() !== selectedUser.full_name || deleting}
              >
                {deleting ? 'Deleting...' : 'Delete Account'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
