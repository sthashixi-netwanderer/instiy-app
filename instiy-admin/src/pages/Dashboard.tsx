import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Users, ShoppingBag, CreditCard, Clock, Landmark, Loader } from 'lucide-react';

interface DashboardStats {
  totalUsers: number;
  verifiedSellers: number;
  totalProducts: number;
  soldProducts: number;
  totalSales: number;
  pendingWithdrawals: number;
}

export const Dashboard: React.FC = () => {
  const [stats, setStats] = useState<DashboardStats>({
    totalUsers: 0,
    verifiedSellers: 0,
    totalProducts: 0,
    soldProducts: 0,
    totalSales: 0,
    pendingWithdrawals: 0,
  });
  const [recentOrders, setRecentOrders] = useState<any[]>([]);
  const [recentWithdrawals, setRecentWithdrawals] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchDashboardData = async () => {
    try {
      setLoading(true);

      const { count: totalUsers } = await supabase
        .from('users').select('*', { count: 'exact', head: true });

      const { count: verifiedSellers } = await supabase
        .from('users').select('*', { count: 'exact', head: true }).eq('is_verified', true);

      const { count: totalProducts } = await supabase
        .from('products').select('*', { count: 'exact', head: true });

      const { count: soldProducts } = await supabase
        .from('products').select('*', { count: 'exact', head: true }).eq('status', 'sold');

      const { count: pendingWithdrawals } = await supabase
        .from('withdrawal_requests').select('*', { count: 'exact', head: true })
        .in('status', ['pending', 'processing']);

      const { data: orderSales } = await supabase
        .from('orders').select('total_amount')
        .neq('status', 'cancelled').eq('payment_status', 'paid');

      const totalSales = (orderSales || []).reduce((sum, item) => sum + Number(item.total_amount || 0), 0);

      setStats({
        totalUsers: totalUsers || 0,
        verifiedSellers: verifiedSellers || 0,
        totalProducts: totalProducts || 0,
        soldProducts: soldProducts || 0,
        totalSales,
        pendingWithdrawals: pendingWithdrawals || 0,
      });

      const { data: orders } = await supabase
        .from('orders')
        .select(`id, buyer_id, total_amount, status, payment_status, created_at, users:buyer_id ( full_name, email )`)
        .order('created_at', { ascending: false }).limit(5);
      setRecentOrders(orders || []);

      const { data: withdrawals } = await supabase
        .from('withdrawal_requests')
        .select(`id, amount_requested, status, method_type, created_at, users:user_id ( full_name, email )`)
        .order('created_at', { ascending: false }).limit(5);
      setRecentWithdrawals(withdrawals || []);
    } catch (error) {
      console.error('Error fetching dashboard data:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchDashboardData(); }, []);

  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '60vh' }}>
        <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
      </div>
    );
  }

  const statCards = [
    {
      label: 'Total Users',
      value: stats.totalUsers.toLocaleString(),
      detail: `${stats.verifiedSellers} verified sellers`,
      detailColor: 'hsl(var(--success-hover))',
      icon: <Users size={20} />,
      iconBg: 'hsl(var(--accent-dim))',
      iconColor: 'hsl(var(--accent))',
    },
    {
      label: 'Products Listed',
      value: stats.totalProducts.toLocaleString(),
      detail: `${stats.soldProducts} sold`,
      detailColor: 'hsl(var(--success-hover))',
      icon: <ShoppingBag size={20} />,
      iconBg: 'hsl(var(--info-dim))',
      iconColor: 'hsl(var(--info))',
    },
    {
      label: 'Transaction Volume',
      value: `GH\u20B5${stats.totalSales.toFixed(2)}`,
      detail: 'Paid orders',
      detailColor: 'hsl(var(--text-tertiary))',
      icon: <CreditCard size={20} />,
      iconBg: 'hsl(var(--success-dim))',
      iconColor: 'hsl(var(--success-hover))',
    },
    {
      label: 'Pending Cashouts',
      value: stats.pendingWithdrawals.toString(),
      detail: 'Awaiting approval',
      detailColor: stats.pendingWithdrawals > 0 ? 'hsl(var(--warning))' : 'hsl(var(--text-tertiary))',
      icon: <Clock size={20} />,
      iconBg: stats.pendingWithdrawals > 0 ? 'hsl(var(--warning-dim))' : 'hsl(var(--accent-subtle))',
      iconColor: stats.pendingWithdrawals > 0 ? 'hsl(var(--warning))' : 'hsl(var(--text-secondary))',
      highlight: stats.pendingWithdrawals > 0,
    },
  ];

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Dashboard</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Platform overview and recent activity</p>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="dashboard-grid">
        {statCards.map((card, i) => (
          <div key={i} className="card" style={card.highlight ? { borderColor: 'hsl(var(--warning) / 0.3)' } : undefined}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div>
                <div className="card-title">{card.label}</div>
                <div className="card-value">{card.value}</div>
                <span style={{ color: card.detailColor, fontSize: '0.78rem', fontWeight: 500 }}>
                  {card.detail}
                </span>
              </div>
              <div style={{
                padding: '0.5rem',
                borderRadius: 'var(--radius-sm)',
                background: card.iconBg,
                color: card.iconColor,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}>
                {card.icon}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Recent Activity Panels */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(400px, 1fr))', gap: '1.25rem', marginTop: '0.5rem' }}>

        {/* Recent Orders */}
        <div className="card">
          <h3 style={{
            fontSize: '0.95rem',
            marginBottom: '1rem',
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
            color: 'hsl(var(--text-secondary))',
            fontWeight: 600,
          }}>
            <ShoppingBag size={16} style={{ color: 'hsl(var(--accent))' }} />
            Recent Orders
          </h3>
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Buyer</th>
                  <th>Total</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {recentOrders.length === 0 ? (
                  <tr>
                    <td colSpan={3} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))' }}>No orders yet</td>
                  </tr>
                ) : (
                  recentOrders.map((order) => (
                    <tr key={order.id}>
                      <td>
                        <div style={{ fontWeight: 600, fontSize: '0.82rem' }}>{order.users?.full_name || 'Unknown'}</div>
                        <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>{order.users?.email}</div>
                      </td>
                      <td style={{ fontWeight: 600, fontSize: '0.82rem' }}>GH&#8373;{order.total_amount}</td>
                      <td>
                        <span className={`badge ${
                          order.status === 'completed' || order.status === 'confirmed' ? 'badge-success' :
                          order.status === 'pending' ? 'badge-warning' : 'badge-danger'
                        }`}>
                          {order.status}
                        </span>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* Recent Cashouts */}
        <div className="card">
          <h3 style={{
            fontSize: '0.95rem',
            marginBottom: '1rem',
            display: 'flex',
            alignItems: 'center',
            gap: '0.5rem',
            color: 'hsl(var(--text-secondary))',
            fontWeight: 600,
          }}>
            <Landmark size={16} style={{ color: 'hsl(var(--warning))' }} />
            Recent Cashouts
          </h3>
          <div className="table-container">
            <table className="table">
              <thead>
                <tr>
                  <th>Seller</th>
                  <th>Amount</th>
                  <th>Method</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {recentWithdrawals.length === 0 ? (
                  <tr>
                    <td colSpan={4} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))' }}>No cashouts yet</td>
                  </tr>
                ) : (
                  recentWithdrawals.map((w) => (
                    <tr key={w.id}>
                      <td>
                        <div style={{ fontWeight: 600, fontSize: '0.82rem' }}>{w.users?.full_name || 'Unknown'}</div>
                        <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>{w.users?.email}</div>
                      </td>
                      <td style={{ fontWeight: 600, fontSize: '0.82rem' }}>GH&#8373;{Number(w.amount_requested).toFixed(2)}</td>
                      <td style={{ textTransform: 'capitalize', fontSize: '0.82rem' }}>{w.method_type.replace('_', ' ')}</td>
                      <td>
                        <span className={`badge ${
                          w.status === 'completed' ? 'badge-success' :
                          w.status === 'pending' || w.status === 'processing' ? 'badge-warning' : 'badge-danger'
                        }`}>
                          {w.status}
                        </span>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};
