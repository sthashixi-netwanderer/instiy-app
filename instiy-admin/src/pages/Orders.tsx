import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Search, Filter, Eye, X, ShoppingCart, Truck, Check, Loader } from 'lucide-react';
import { useAlert, useConfirm } from '../components/use-alert';
import { formatGhs } from "../utils/format";

export const Orders: React.FC = () => {
  const [orders, setOrders] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedStatus, setSelectedStatus] = useState('');
  const [selectedPaymentStatus, setSelectedPaymentStatus] = useState('');

  const [selectedOrder, setSelectedOrder] = useState<any>(null);
  const [orderItems, setOrderItems] = useState<any[]>([]);
  const [loadingItems, setLoadingItems] = useState(false);
  const [processingAction, setProcessingAction] = useState(false);
  const { alert, AlertComponent } = useAlert();
  const { confirm, ConfirmComponent } = useConfirm();
  const [payReference, setPayReference] = useState('');
  const [showPayInput, setShowPayInput] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  const fetchOrders = async () => {
    try {
      setLoading(true);
      setFetchError(null);
      let query = supabase
        .from('orders')
        .select(`*, users:buyer_id ( full_name, email )`)
        .order('created_at', { ascending: false });

      if (selectedStatus) query = query.eq('status', selectedStatus);
      if (selectedPaymentStatus) query = query.eq('payment_status', selectedPaymentStatus);

      const { data, error } = await query;
      if (error) throw error;

      let result = data || [];
      if (searchQuery.trim() !== '') {
        const q = searchQuery.trim().toLowerCase();
        result = result.filter((o: any) =>
          o.id?.toLowerCase().includes(q) ||
          (o.users?.full_name as string | undefined)?.toLowerCase().includes(q) ||
          (o.users?.email as string | undefined)?.toLowerCase().includes(q)
        );
      }
      setOrders(result);
    } catch (error: any) {
      console.error('Error fetching orders:', error);
      setFetchError(error?.message || 'Failed to load orders.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchOrders(); }, [searchQuery, selectedStatus, selectedPaymentStatus]);

  const viewOrderDetails = async (order: any) => {
    setSelectedOrder(order);
    setLoadingItems(true);
    setOrderItems([]);
    setShowPayInput(false);
    setPayReference('');

    try {
      const { data, error } = await supabase
        .from('order_items').select(`*, users:seller_id ( full_name, email )`).eq('order_id', order.id);
      if (error) throw error;
      setOrderItems(data || []);
    } catch (e) {
      console.error('Error fetching items:', e);
    } finally {
      setLoadingItems(false);
    }
  };

  const handleMarkAsPaid = async () => {
    if (!selectedOrder) return;
    setProcessingAction(true);
    try {
      const { error } = await supabase.rpc('mark_order_paid', {
        p_order_id: selectedOrder.id, p_reference: payReference.trim() || null
      });
      if (error) throw error;
      alert('Success', { description: 'Order marked as paid.', variant: 'success' });
      setOrders(orders.map(o => o.id === selectedOrder.id ? { ...o, payment_status: 'paid', status: 'confirmed' } : o));
      setSelectedOrder({ ...selectedOrder, payment_status: 'paid', status: 'confirmed' });
      setShowPayInput(false);
    } catch (error) {
      alert('Error', { description: 'Error: ' + (error as any).message, variant: 'danger' });
    } finally {
      setProcessingAction(false);
    }
  };

  const handleCancelOrder = () => {
    if (!selectedOrder) return;
    confirm('Cancel Order', async () => {
      setProcessingAction(true);
      try {
        const { error } = await supabase.rpc('cancel_order', { order_id: selectedOrder.id });
        if (error) throw error;
        alert('Success', { description: 'Order cancelled and buyer refunded.', variant: 'success' });
        setOrders(orders.map(o => o.id === selectedOrder.id ? { ...o, status: 'cancelled' } : o));
        setSelectedOrder({ ...selectedOrder, status: 'cancelled' });

        // Send cancellation email to buyer
        const buyerEmail = selectedOrder.users?.email;
        if (buyerEmail) {
          try {
            await supabase.functions.invoke('send-email', {
              body: {
                to: buyerEmail,
                subject: `Order Cancelled - Refund Processed (${selectedOrder.id.substring(0, 8)})`,
                html: `
                  <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background: #fafaf8; border-radius: 12px;">
                    <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
                    <h2 style="color: #2d2a26; margin-bottom: 8px;">Order Cancelled</h2>
                    <p style="color: #6b6560; line-height: 1.6;">
                      Hello ${selectedOrder.users?.full_name || 'there'},
                    </p>
                    <p style="color: #6b6560; line-height: 1.6;">
                      Your order <strong>#${selectedOrder.id.substring(0, 8)}</strong> has been cancelled by our admin team.
                    </p>
                    <div style="background: #fff; border: 1px solid #e8e5e0; border-radius: 8px; padding: 16px; margin: 16px 0;">
                      <p style="margin: 0; color: #2d2a26;"><strong>Order ID:</strong> ${selectedOrder.id.substring(0, 8)}</p>
                      <p style="margin: 8px 0 0; color: #2d2a26;"><strong>Refund Amount:</strong> {formatGhs(selectedOrder.total_amount)}</p>
                      <p style="margin: 8px 0 0; color: #2d2a26;"><strong>Refund Method:</strong> Wallet Credit</p>
                    </div>
                    <p style="color: #6b6560; line-height: 1.6; font-size: 14px;">
                      The full amount has been credited back to your Instiy wallet. You can use it for future purchases or request a withdrawal.
                    </p>
                    <p style="color: #6b6560; line-height: 1.6; font-size: 14px;">
                      If you have any questions, please contact our support team.
                    </p>
                    <p style="color: #9a9590; font-size: 12px; margin-top: 24px; border-top: 1px solid #e8e5e0; padding-top: 12px;">
                      Instiy — Campus Marketplace
                    </p>
                  </div>
                `
              }
            });
          } catch (emailErr) {
            console.error('Failed to send cancellation email:', emailErr);
          }
        }
      } catch (error) {
        alert('Error', { description: 'Error: ' + (error as any).message, variant: 'danger' });
      } finally {
        setProcessingAction(false);
      }
    }, { confirmLabel: 'Cancel Order', variant: 'danger' });
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Orders</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.25rem', fontSize: '0.85rem' }}>Track orders, manage payments and statuses</p>
        </div>
      </div>

      {/* Filters */}
      <div className="card" style={{ marginBottom: '1.5rem', display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '240px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
              placeholder="Search by buyer, email, or UUID..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
          </div>
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem' }}>
              <Filter size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
              <select className="form-control" style={{ width: '140px', padding: '0.45rem' }} value={selectedStatus} onChange={(e) => setSelectedStatus(e.target.value)}>
                <option value="">All Statuses</option>
                <option value="pending">Pending</option>
                <option value="confirmed">Confirmed</option>
                <option value="completed">Completed</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </div>
            <select className="form-control" style={{ width: '140px', padding: '0.45rem' }} value={selectedPaymentStatus} onChange={(e) => setSelectedPaymentStatus(e.target.value)}>
              <option value="">All Payments</option>
              <option value="paid">Paid</option>
              <option value="unpaid">Unpaid</option>
            </select>
          </div>
        </div>
      </div>

      {fetchError && (
        <div style={{
          background: 'hsl(var(--danger-dim))', border: '1px solid hsl(var(--danger) / 0.3)',
          borderRadius: 'var(--radius-sm)', padding: '0.75rem 1rem', marginBottom: '1rem',
          color: 'hsl(var(--danger-hover))', fontSize: '0.82rem', display: 'flex', alignItems: 'center', gap: '0.5rem',
        }}>
          <X size={14} /> {fetchError}
        </div>
      )}

      {/* Table */}
      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th>Order ID</th>
                <th>Buyer</th>
                <th>Total</th>
                <th>Items</th>
                <th>Delivery</th>
                <th>Status</th>
                <th>Payment</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {orders.length === 0 ? (
                <tr><td colSpan={8} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))', padding: '2rem' }}>No orders found</td></tr>
              ) : orders.map((o) => (
                <tr key={o.id}>
                  <td style={{ fontFamily: 'var(--font-title)', fontSize: '0.75rem', fontWeight: 600 }}>{o.id.substring(0, 8)}...</td>
                  <td>
                    <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{o.users?.full_name || 'N/A'}</div>
                    <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>{o.users?.email}</div>
                  </td>
                  <td style={{ fontWeight: 700 }}>{formatGhs(o.total_amount)}</td>
                  <td style={{ fontSize: '0.82rem' }}>{o.item_quantity_total} items</td>
                  <td style={{ textTransform: 'capitalize', fontSize: '0.82rem' }}>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                      {o.delivery_mode === 'delivery' ? <Truck size={13} /> : <ShoppingCart size={13} />}
                      {o.delivery_mode}
                    </span>
                  </td>
                  <td>
                    <span className={`badge ${o.status === 'completed' || o.status === 'confirmed' ? 'badge-success' : o.status === 'pending' ? 'badge-warning' : 'badge-danger'}`}>
                      {o.status}
                    </span>
                  </td>
                  <td>
                    <span className={`badge ${o.payment_status === 'paid' ? 'badge-success' : 'badge-warning'}`}>{o.payment_status}</span>
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => viewOrderDetails(o)}>
                        <Eye size={13} /> View
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Order Drawer */}
      {selectedOrder && (
        <div className="drawer-backdrop" onClick={() => setSelectedOrder(null)}>
          <div className="drawer" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.875rem' }}>
              <h2 style={{ fontSize: '1.25rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <ShoppingCart size={20} style={{ color: 'hsl(var(--accent))' }} /> Order Details
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => setSelectedOrder(null)}><X size={20} /></button>
            </div>

            {/* Info Card */}
            <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', background: 'hsl(var(--bg-surface))' }}>
              {[
                ['Order ID', selectedOrder.id],
                ['Buyer', `${selectedOrder.users?.full_name} (${selectedOrder.users?.email})`],
                ['Payment', selectedOrder.payment_status],
                ...(selectedOrder.payment_reference ? [['Ref', selectedOrder.payment_reference]] : []),
                ['Created', new Date(selectedOrder.created_at).toLocaleString()],
              ].map(([label, value]) => (
                <div key={label} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                  <span style={{ color: 'hsl(var(--text-tertiary))' }}>{label}:</span>
                  <span style={{ fontFamily: label === 'Order ID' ? 'var(--font-title)' : 'inherit', fontSize: label === 'Order ID' ? '0.75rem' : 'inherit' }}>{value}</span>
                </div>
              ))}
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem', borderTop: '1px solid hsl(var(--border))', paddingTop: '0.5rem', marginTop: '0.125rem' }}>
                <span style={{ color: 'hsl(var(--text-tertiary))' }}>Payment:</span>
                <span className={`badge ${selectedOrder.payment_status === 'paid' ? 'badge-success' : 'badge-warning'}`}>{selectedOrder.payment_status}</span>
              </div>
            </div>

            {/* Items */}
            <div>
              <h3 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.625rem', textTransform: 'uppercase', letterSpacing: '0.06em' }}>Items Ordered</h3>
              {loadingItems ? (
                <div style={{ display: 'flex', justifyContent: 'center', padding: '0.75rem' }}><Loader className="spin" size={18} /></div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                  {orderItems.map((item) => (
                    <div key={item.id} className="card" style={{ padding: '0.625rem', display: 'flex', gap: '0.625rem', alignItems: 'center', background: 'hsl(var(--bg-surface))' }}>
                      <img src={item.product_thumbnail || 'https://placehold.co/100x100?text=No+Image'} alt={item.product_title}
                        style={{ width: '40px', height: '40px', borderRadius: '4px', objectFit: 'cover' }} />
                      <div style={{ flex: 1 }}>
                        <div style={{ fontWeight: 600, fontSize: '0.82rem' }}>{item.product_title}</div>
                        <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>Seller: {item.users?.full_name || 'N/A'}</div>
                        <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>
                          Code: <code style={{ color: 'hsl(var(--accent))', fontWeight: 'bold' }}>{item.delivery_code || 'N/A'}</code> | <span className="badge badge-info" style={{ padding: '1px 4px', fontSize: '0.62rem' }}>{item.status}</span>
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <div style={{ fontWeight: 700, fontSize: '0.85rem' }}>{formatGhs(item.price * item.quantity)}</div>
                        <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>{item.quantity} x {formatGhs(item.price)}</div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {/* Total */}
            <div style={{ borderTop: '1px solid hsl(var(--border))', paddingTop: '0.875rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontWeight: 600, fontSize: '0.9rem' }}>Total:</span>
              <span style={{ fontSize: '1.35rem', fontWeight: 700, fontFamily: 'var(--font-title)' }}>
                {formatGhs(selectedOrder.total_amount)}
              </span>
            </div>

            {/* Actions */}
            <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
              <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.06em' }}>Actions</h4>
              {showPayInput ? (
                <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.625rem' }}>
                  <div className="form-group" style={{ marginBottom: 0 }}>
                    <label className="form-label">Payment Reference (optional)</label>
                    <input type="text" className="form-control" placeholder="e.g. PAYSTACK-REF-123" value={payReference} onChange={(e) => setPayReference(e.target.value)} />
                  </div>
                  <div style={{ display: 'flex', gap: '0.5rem' }}>
                    <button className="btn btn-secondary btn-sm" style={{ flex: 1 }} onClick={() => setShowPayInput(false)}>Cancel</button>
                    <button className="btn btn-success btn-sm" style={{ flex: 1 }} onClick={handleMarkAsPaid} disabled={processingAction}>Confirm Paid</button>
                  </div>
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.625rem' }}>
                  {selectedOrder.payment_status !== 'paid' && selectedOrder.status !== 'cancelled' && (
                    <button className="btn btn-success" onClick={() => setShowPayInput(true)}>
                      <Check size={14} /> Mark Paid
                    </button>
                  )}
                  {selectedOrder.status !== 'cancelled' && selectedOrder.status !== 'completed' && (
                    <button className="btn btn-danger" onClick={handleCancelOrder} disabled={processingAction}>
                      <X size={14} /> Cancel Order
                    </button>
                  )}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
      {AlertComponent}
      {ConfirmComponent}
    </div>
  );
};
