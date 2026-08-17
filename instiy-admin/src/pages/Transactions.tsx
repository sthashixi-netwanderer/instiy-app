import React, { useEffect, useState, useMemo } from 'react';
import { supabase } from '../supabaseClient';
import { 
  Search, Filter, Loader, Eye, Wallet, RefreshCw, 
  Calendar, ArrowLeftRight, Copy, User, AlertCircle
} from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '../components/dialog';
import { useAlert } from '../components/use-alert';

interface UserInfo {
  id: string;
  full_name: string;
  email: string;
  phone_number: string;
  avatar_url?: string;
}

interface WalletInfo {
  id: string;
  balance: number;
}

interface Transaction {
  id: string;
  type: 'deposit' | 'withdrawal' | 'transfer_in' | 'transfer_out' | 'payment' | 'refund';
  amount: number;
  balance_before: number;
  balance_after: number;
  description?: string;
  reference?: string;
  source?: string;
  created_at: string;
  wallet_id: string;
}

interface UserGroup {
  user: UserInfo;
  wallet: WalletInfo;
  transactions: Transaction[];
  transactionCount: number;
  totalDeposit: number;
  totalWithdrawal: number;
  totalSpent: number;
  lastTransactionDate?: string;
}

export const Transactions: React.FC = () => {
  const [allGroups, setAllGroups] = useState<UserGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  
  // Search & Filter State
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [balanceFilter, setBalanceFilter] = useState('all');
  const [dateFilter, setDateFilter] = useState('all');
  
  // Detail Modal State
  const [selectedGroup, setSelectedGroup] = useState<UserGroup | null>(null);
  const [modalSearch, setModalSearch] = useState('');
  const [modalTypeFilter, setModalTypeFilter] = useState('all');
  const [copiedId, setCopiedId] = useState<string | null>(null);
  
  const { AlertComponent } = useAlert();

  const fetchTransactionsData = async () => {
    try {
      setLoading(true);
      setErrorMsg(null);

      // 1. Fetch wallets with user relationships
      const { data: walletsData, error: walletsError } = await supabase
        .from('wallets')
        .select(`
          id,
          balance,
          user_id,
          users (
            id,
            full_name,
            email,
            phone_number,
            avatar_url
          )
        `);

      if (walletsError) throw walletsError;

      // 2. Fetch all wallet transactions
      const { data: txsData, error: txsError } = await supabase
        .from('wallet_transactions')
        .select('*')
        .order('created_at', { ascending: false });

      if (txsError) throw txsError;

      const walletMap: { [id: string]: any } = {};
      walletsData?.forEach(w => {
        walletMap[w.id] = w;
      });

      const groups: { [userId: string]: UserGroup } = {};

      // Initialize all groups
      walletsData?.forEach(w => {
        const user: any = w.users;
        if (!user) return;
        groups[user.id] = {
          user: {
            id: user.id,
            full_name: user.full_name || 'Unknown User',
            email: user.email || 'N/A',
            phone_number: user.phone_number || 'N/A',
            avatar_url: user.avatar_url
          },
          wallet: {
            id: w.id,
            balance: Number(w.balance || 0)
          },
          transactions: [],
          transactionCount: 0,
          totalDeposit: 0,
          totalWithdrawal: 0,
          totalSpent: 0
        };
      });

      // Populate transactions
      txsData?.forEach((tx: any) => {
        const wallet = walletMap[tx.wallet_id];
        if (!wallet || !wallet.users) return;
        const userId = wallet.users.id;
        const group = groups[userId];
        if (!group) return;

        const amt = Number(tx.amount || 0);
        group.transactions.push(tx);
        group.transactionCount++;

        if (!group.lastTransactionDate) {
          group.lastTransactionDate = tx.created_at;
        }

        // Sum transaction volumes
        if (tx.type === 'deposit' || tx.type === 'transfer_in' || tx.type === 'refund') {
          group.totalDeposit += amt;
        } else if (tx.type === 'withdrawal') {
          group.totalWithdrawal += amt;
        } else if (tx.type === 'payment' || tx.type === 'transfer_out') {
          group.totalSpent += amt;
        }
      });

      setAllGroups(Object.values(groups));
    } catch (err: any) {
      console.error('Error fetching transactions:', err);
      setErrorMsg(err.message || 'Failed to load transaction records.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchTransactionsData();
  }, []);

  const handleCopy = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 1500);
  };

  // Main UI statistics
  const globalStats = useMemo(() => {
    let totalTxCount = 0;
    let totalBalance = 0;
    let totalDeposits = 0;
    let totalWithdrawals = 0;
    let totalSpent = 0;

    allGroups.forEach(g => {
      totalBalance += g.wallet.balance;
      totalTxCount += g.transactionCount;
      totalDeposits += g.totalDeposit;
      totalWithdrawals += g.totalWithdrawal;
      totalSpent += g.totalSpent;
    });

    return {
      totalTxCount,
      totalBalance,
      totalDeposits,
      totalWithdrawals,
      totalSpent
    };
  }, [allGroups]);

  // Main List Filtering
  const filteredGroups = useMemo(() => {
    return allGroups.filter(g => {
      // 1. Search Query (matches user profile or transaction details)
      if (searchQuery.trim() !== '') {
        const q = searchQuery.toLowerCase();
        const matchesUser = 
          g.user.full_name.toLowerCase().includes(q) ||
          g.user.email.toLowerCase().includes(q) ||
          g.user.phone_number.toLowerCase().includes(q) ||
          g.user.id.toLowerCase().includes(q);

        const matchesTx = g.transactions.some(tx => 
          tx.id.toLowerCase().includes(q) ||
          (tx.reference && tx.reference.toLowerCase().includes(q)) ||
          (tx.description && tx.description.toLowerCase().includes(q))
        );

        if (!matchesUser && !matchesTx) return false;
      }

      // 2. Type Filter
      if (typeFilter !== 'all') {
        const hasType = g.transactions.some(tx => {
          if (typeFilter === 'transfer') {
            return tx.type === 'transfer_in' || tx.type === 'transfer_out';
          }
          return tx.type === typeFilter;
        });
        if (!hasType) return false;
      }

      // 3. Balance Filter
      if (balanceFilter === 'has_balance' && g.wallet.balance <= 0) return false;
      if (balanceFilter === 'zero_balance' && g.wallet.balance !== 0) return false;

      // 4. Date Filter
      if (dateFilter !== 'all') {
        const now = new Date();
        const limitDate = new Date();
        if (dateFilter === 'today') {
          limitDate.setHours(0, 0, 0, 0);
        } else if (dateFilter === 'week') {
          limitDate.setDate(now.getDate() - 7);
        } else if (dateFilter === 'month') {
          limitDate.setMonth(now.getMonth() - 1);
        }

        const hasTxInRange = g.transactions.some(tx => {
          const txDate = new Date(tx.created_at);
          return txDate >= limitDate;
        });
        if (!hasTxInRange) return false;
      }

      return true;
    });
  }, [allGroups, searchQuery, typeFilter, balanceFilter, dateFilter]);

  // Modal List Filtering
  const filteredModalTransactions = useMemo(() => {
    if (!selectedGroup) return [];
    return selectedGroup.transactions.filter(tx => {
      if (modalSearch.trim() !== '') {
        const q = modalSearch.toLowerCase();
        const matches = 
          tx.id.toLowerCase().includes(q) ||
          (tx.reference && tx.reference.toLowerCase().includes(q)) ||
          (tx.description && tx.description.toLowerCase().includes(q)) ||
          (tx.source && tx.source.toLowerCase().includes(q));
        if (!matches) return false;
      }

      if (modalTypeFilter !== 'all') {
        if (modalTypeFilter === 'transfer') {
          return tx.type === 'transfer_in' || tx.type === 'transfer_out';
        }
        return tx.type === modalTypeFilter;
      }

      return true;
    });
  }, [selectedGroup, modalSearch, modalTypeFilter]);

  const formatCurrency = (value: number) => {
    return `GHS ${value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };

  const formatDate = (dateStr: string) => {
    const d = new Date(dateStr);
    return d.toLocaleString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  const getTransactionBadgeClass = (type: string) => {
    switch (type) {
      case 'deposit':
      case 'transfer_in':
      case 'refund':
        return 'badge-success';
      case 'withdrawal':
      case 'transfer_out':
      case 'payment':
        return 'badge-danger';
      default:
        return 'badge-info';
    }
  };

  const getTransactionTypeLabel = (type: string) => {
    switch (type) {
      case 'deposit': return 'Deposit';
      case 'withdrawal': return 'Withdrawal';
      case 'transfer_in': return 'Transfer In';
      case 'transfer_out': return 'Transfer Out';
      case 'payment': return 'Payment';
      case 'refund': return 'Refund';
      default: return type;
    }
  };

  return (
    <div className="animated-fade-in">
      {/* Page Header */}
      <div className="page-header">
        <div>
          <h1 className="page-title">Transaction History</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.25rem', fontSize: '0.85rem' }}>
            Review, track, and audit transaction records grouped by users.
          </p>
        </div>
        <button className="btn btn-secondary" onClick={fetchTransactionsData} disabled={loading}>
          <RefreshCw size={16} className={loading ? 'spin' : ''} />
          Refresh
        </button>
      </div>

      {/* Global Stat Cards */}
      <div className="dashboard-grid">
        <div className="card">
          <div className="card-title">Total Active Balances</div>
          <div className="card-value" style={{ color: 'hsl(var(--accent))' }}>
            {formatCurrency(globalStats.totalBalance)}
          </div>
          <p style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>Combined user wallet balances</p>
        </div>
        <div className="card">
          <div className="card-title">Total Transactions</div>
          <div className="card-value">
            {globalStats.totalTxCount}
          </div>
          <p style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>System-wide transaction events</p>
        </div>
        <div className="card">
          <div className="card-title">Total Inflows (Deposits)</div>
          <div className="card-value" style={{ color: 'hsl(var(--success))' }}>
            {formatCurrency(globalStats.totalDeposits)}
          </div>
          <p style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>Deposits, transfers in & refunds</p>
        </div>
        <div className="card">
          <div className="card-title">Total Outflows</div>
          <div className="card-value" style={{ color: 'hsl(var(--danger-hover))' }}>
            {formatCurrency(globalStats.totalWithdrawals + globalStats.totalSpent)}
          </div>
          <p style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>Withdrawals, transfers out & payments</p>
        </div>
      </div>

      {/* Filter and Search Bar */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '240px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input 
              type="text" 
              className="form-control" 
              style={{ paddingLeft: '2.25rem' }}
              placeholder="Search by User Name, Email, ID or Transaction Ref..." 
              value={searchQuery} 
              onChange={(e) => setSearchQuery(e.target.value)} 
            />
          </div>

          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
            {/* Type Filter */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
              <Filter size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
              <select className="form-control" style={{ width: '130px', padding: '0.45rem' }} value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}>
                <option value="all">All Types</option>
                <option value="deposit">Deposit</option>
                <option value="withdrawal">Withdrawal</option>
                <option value="payment">Payment</option>
                <option value="refund">Refund</option>
                <option value="transfer">Transfers</option>
              </select>
            </div>

            {/* Balance Filter */}
            <select className="form-control" style={{ width: '140px', padding: '0.45rem' }} value={balanceFilter} onChange={(e) => setBalanceFilter(e.target.value)}>
              <option value="all">All Balances</option>
              <option value="has_balance">Positive Balance</option>
              <option value="zero_balance">Zero Balance</option>
            </select>

            {/* Date Range Filter */}
            <select className="form-control" style={{ width: '140px', padding: '0.45rem' }} value={dateFilter} onChange={(e) => setDateFilter(e.target.value)}>
              <option value="all">All Time</option>
              <option value="today">Today</option>
              <option value="week">Past 7 Days</option>
              <option value="month">Past 30 Days</option>
            </select>
          </div>
        </div>
      </div>

      {/* Main Table Content */}
      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : errorMsg ? (
        <div className="card" style={{ padding: '2rem', textAlign: 'center', color: 'hsl(var(--danger-hover))' }}>
          <AlertCircle size={40} style={{ margin: '0 auto 0.75rem', display: 'block' }} />
          <h3 style={{ fontSize: '1.1rem', fontWeight: 600 }}>Error Loading Records</h3>
          <p style={{ marginTop: '0.5rem', color: 'hsl(var(--text-secondary))' }}>{errorMsg}</p>
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>User Profile</th>
                <th>User ID</th>
                <th>Wallet Balance</th>
                <th style={{ textAlign: 'center' }}>Transactions</th>
                <th>Total Volume (In / Out)</th>
                <th>Last Active</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredGroups.length === 0 ? (
                <tr>
                  <td colSpan={7} style={{ textAlign: 'center', padding: '3rem', color: 'hsl(var(--text-tertiary))' }}>
                    <ArrowLeftRight size={36} style={{ margin: '0 auto 0.75rem', display: 'block', opacity: 0.3 }} />
                    No user transaction history matches the filter criteria.
                  </td>
                </tr>
              ) : (
                filteredGroups.map((g) => (
                  <tr key={g.user.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                        {g.user.avatar_url ? (
                          <img 
                            src={g.user.avatar_url} 
                            alt={g.user.full_name} 
                            style={{ width: '36px', height: '36px', borderRadius: '50%', objectFit: 'cover', border: '1px solid hsl(var(--border))' }}
                          />
                        ) : (
                          <div style={{ 
                            width: '36px', height: '36px', borderRadius: '50%', background: 'hsl(var(--accent-dim))',
                            display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'hsl(var(--accent))'
                          }}>
                            <User size={16} />
                          </div>
                        )}
                        <div style={{ minWidth: 0 }}>
                          <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'hsl(var(--text-main))' }}>{g.user.full_name}</div>
                          <div style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', textOverflow: 'ellipsis', overflow: 'hidden', whiteSpace: 'nowrap' }}>{g.user.email}</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                        <code style={{ fontSize: '0.75rem', color: 'hsl(var(--text-secondary))' }}>
                          {g.user.id.substring(0, 8)}...
                        </code>
                        <button 
                          className="btn btn-secondary btn-sm" 
                          style={{ padding: '2px', background: 'none', border: 'none' }}
                          onClick={() => handleCopy(g.user.id, `usr-${g.user.id}`)}
                          title="Copy User ID"
                        >
                          <Copy size={10} style={{ color: copiedId === `usr-${g.user.id}` ? 'hsl(var(--success))' : 'hsl(var(--text-tertiary))' }} />
                        </button>
                      </div>
                    </td>
                    <td style={{ fontWeight: 700, color: g.wallet.balance > 0 ? 'hsl(var(--accent))' : 'hsl(var(--text-secondary))' }}>
                      {formatCurrency(g.wallet.balance)}
                    </td>
                    <td style={{ textAlign: 'center' }}>
                      <span className="badge badge-info" style={{ fontSize: '0.75rem' }}>{g.transactionCount} txs</span>
                    </td>
                    <td>
                      <div style={{ fontSize: '0.78rem' }}>
                        <div style={{ color: 'hsl(var(--success-hover))' }}>
                          In: {formatCurrency(g.totalDeposit)}
                        </div>
                        <div style={{ color: 'hsl(var(--text-secondary))' }}>
                          Out: {formatCurrency(g.totalWithdrawal + g.totalSpent)}
                        </div>
                      </div>
                    </td>
                    <td style={{ fontSize: '0.78rem', color: 'hsl(var(--text-secondary))' }}>
                      {g.lastTransactionDate ? (
                        <>
                          <Calendar size={10} style={{ marginRight: '4px', display: 'inline' }} />
                          {formatDate(g.lastTransactionDate)}
                        </>
                      ) : (
                        'No history'
                      )}
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <button 
                        className="btn btn-primary btn-sm" 
                        onClick={() => {
                          setSelectedGroup(g);
                          setModalSearch('');
                          setModalTypeFilter('all');
                        }}
                      >
                        <Eye size={12} /> View Records
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Transaction Details Modal */}
      <Dialog open={selectedGroup !== null} onOpenChange={(open) => { if (!open) setSelectedGroup(null); }}>
        <DialogContent style={{ maxWidth: '880px', maxHeight: '90vh', display: 'flex', flexDirection: 'column' }}>
          <DialogHeader>
            <DialogTitle style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <Wallet size={20} style={{ color: 'hsl(var(--accent))' }} />
              <span>Wallet Records: {selectedGroup?.user.full_name}</span>
            </DialogTitle>
            <DialogDescription>
              User ID: <code style={{ color: 'hsl(var(--accent))' }}>{selectedGroup?.user.id}</code> | Email: {selectedGroup?.user.email} | Wallet ID: <code style={{ fontSize: '0.7rem' }}>{selectedGroup?.wallet.id}</code>
            </DialogDescription>
          </DialogHeader>

          {/* Modal Filters */}
          <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '1rem', flexWrap: 'wrap' }}>
            <div style={{ position: 'relative', flex: 1, minWidth: '200px' }}>
              <Search size={14} style={{ position: 'absolute', left: '8px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
              <input 
                type="text" 
                className="form-control" 
                style={{ paddingLeft: '2rem', paddingTop: '0.45rem', paddingBottom: '0.45rem', fontSize: '0.8rem' }}
                placeholder="Search tx ID, reference, description..." 
                value={modalSearch}
                onChange={(e) => setModalSearch(e.target.value)}
              />
            </div>
            
            <select 
              className="form-control" 
              style={{ width: '130px', padding: '0.45rem', fontSize: '0.8rem' }} 
              value={modalTypeFilter} 
              onChange={(e) => setModalTypeFilter(e.target.value)}
            >
              <option value="all">All Types</option>
              <option value="deposit">Deposit</option>
              <option value="withdrawal">Withdrawal</option>
              <option value="payment">Payment</option>
              <option value="refund">Refund</option>
              <option value="transfer">Transfers</option>
            </select>

            <div style={{ 
              display: 'flex', alignItems: 'center', background: 'hsl(var(--bg-surface))', 
              padding: '0.45rem 0.75rem', borderRadius: 'var(--radius-sm)', border: '1px solid hsl(var(--border))',
              fontSize: '0.8rem', fontWeight: 600
            }}>
              Current Balance: <span style={{ color: 'hsl(var(--accent))', marginLeft: '0.375rem' }}>{selectedGroup && formatCurrency(selectedGroup.wallet.balance)}</span>
            </div>
          </div>

          {/* Modal Table container */}
          <div style={{ flex: 1, overflowY: 'auto', border: '1px solid hsl(var(--border))', borderRadius: 'var(--radius-md)', maxHeight: '50vh' }}>
            <table className="table" style={{ fontSize: '0.8rem' }}>
              <thead style={{ position: 'sticky', top: 0, zIndex: 10 }}>
                <tr>
                  <th>Transaction ID</th>
                  <th>Type</th>
                  <th>Amount</th>
                  <th>Balance Flow</th>
                  <th>Description & Source</th>
                  <th>Reference</th>
                  <th>Date & Time</th>
                </tr>
              </thead>
              <tbody>
                {filteredModalTransactions.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: 'center', padding: '2rem', color: 'hsl(var(--text-tertiary))' }}>
                      No transaction records match the filters.
                    </td>
                  </tr>
                ) : (
                  filteredModalTransactions.map((tx) => (
                    <tr key={tx.id}>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                          <code style={{ fontSize: '0.7rem', color: 'hsl(var(--text-secondary))' }}>
                            {tx.id.substring(0, 8)}...
                          </code>
                          <button 
                            className="btn btn-secondary btn-sm" 
                            style={{ padding: '2px', background: 'none', border: 'none' }}
                            onClick={() => handleCopy(tx.id, tx.id)}
                            title="Copy Tx ID"
                          >
                            <Copy size={9} style={{ color: copiedId === tx.id ? 'hsl(var(--success))' : 'hsl(var(--text-tertiary))' }} />
                          </button>
                        </div>
                      </td>
                      <td>
                        <span className={`badge ${getTransactionBadgeClass(tx.type)}`} style={{ fontSize: '0.65rem', padding: '1px 5px' }}>
                          {getTransactionTypeLabel(tx.type)}
                        </span>
                      </td>
                      <td style={{ 
                        fontWeight: 700, 
                        color: (tx.type === 'deposit' || tx.type === 'transfer_in' || tx.type === 'refund') ? 'hsl(var(--success-hover))' : 'hsl(var(--danger-hover))' 
                      }}>
                        {(tx.type === 'deposit' || tx.type === 'transfer_in' || tx.type === 'refund') ? '+' : '-'} {formatCurrency(Number(tx.amount))}
                      </td>
                      <td style={{ color: 'hsl(var(--text-secondary))', fontSize: '0.75rem' }}>
                        <div>{formatCurrency(Number(tx.balance_before))}</div>
                        <div style={{ fontSize: '0.68rem', opacity: 0.6 }}>&rarr; {formatCurrency(Number(tx.balance_after))}</div>
                      </td>
                      <td>
                        <div style={{ fontWeight: 500 }}>{tx.description || 'No description'}</div>
                        {tx.source && (
                          <div style={{ fontSize: '0.68rem', color: 'hsl(var(--text-tertiary))' }}>
                            Source: <code>{tx.source}</code>
                          </div>
                        )}
                      </td>
                      <td>
                        {tx.reference ? (
                          <div style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                            <span style={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>{tx.reference}</span>
                            <button 
                              className="btn btn-secondary btn-sm" 
                              style={{ padding: '2px', background: 'none', border: 'none' }}
                              onClick={() => handleCopy(tx.reference || '', `ref-${tx.id}`)}
                              title="Copy Reference"
                            >
                              <Copy size={9} style={{ color: copiedId === `ref-${tx.id}` ? 'hsl(var(--success))' : 'hsl(var(--text-tertiary))' }} />
                            </button>
                          </div>
                        ) : (
                          <span style={{ color: 'hsl(var(--text-tertiary))' }}>-</span>
                        )}
                      </td>
                      <td style={{ color: 'hsl(var(--text-secondary))', whiteSpace: 'nowrap' }}>
                        {formatDate(tx.created_at)}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '1rem' }}>
            <button className="btn btn-secondary" onClick={() => setSelectedGroup(null)}>Close</button>
          </div>
        </DialogContent>
      </Dialog>

      {AlertComponent}
    </div>
  );
};
