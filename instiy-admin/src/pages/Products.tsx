import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Search, Filter, Eye, Trash2, Loader, Tag, User, MapPin, Package, X } from 'lucide-react';
import { useAlert, useConfirm } from '../components/use-alert';
import { formatGhs } from "../utils/format";

export const Products: React.FC = () => {
  const [products, setProducts] = useState<any[]>([]);
  const [categories, setCategories] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [selectedStatus, setSelectedStatus] = useState('');
  const [selectedCondition, setSelectedCondition] = useState('');
  const [selectedProduct, setSelectedProduct] = useState<any>(null);
  const [editPrice, setEditPrice] = useState('');
  const [editStock, setEditStock] = useState('');
  const [editStatus, setEditStatus] = useState('');
  const [updating, setUpdating] = useState(false);
  const { alert, AlertComponent } = useAlert();
  const { confirm, ConfirmComponent } = useConfirm();

  const fetchCategories = async () => {
    try {
      const { data } = await supabase.from('categories').select('id, name');
      setCategories(data || []);
    } catch (e) { console.error(e); }
  };

  const fetchProducts = async () => {
    try {
      setLoading(true);
      let query = supabase
        .from('products')
        .select(`*, users:seller_id ( full_name, email ), categories:category_id ( name )`)
        .order('created_at', { ascending: false });

      if (searchQuery.trim()) query = query.or(`title.ilike.%${searchQuery}%,description.ilike.%${searchQuery}%`);
      if (selectedCategory) query = query.eq('category_id', selectedCategory);
      if (selectedStatus) query = query.eq('status', selectedStatus);
      if (selectedCondition) query = query.eq('condition', selectedCondition);

      const { data, error } = await query;
      if (error) throw error;
      setProducts(data || []);
    } catch (error) {
      console.error('Error fetching products:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchCategories(); }, []);
  useEffect(() => { fetchProducts(); }, [searchQuery, selectedCategory, selectedStatus, selectedCondition]);

  const openProductDetails = (product: any) => {
    setSelectedProduct(product);
    setEditPrice(product.price.toString());
    setEditStock(product.stock_quantity.toString());
    setEditStatus(product.status);
  };

  const handleUpdateProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedProduct) return;
    setUpdating(true);
    try {
      const stock = parseInt(editStock);
      let status = editStatus;
      if (stock > 0 && status === 'sold') status = 'available';
      else if (stock === 0 && status === 'available') status = 'sold';

      const { error } = await supabase.from('products').update({
        price: parseFloat(editPrice), stock_quantity: stock, status, updated_at: new Date().toISOString()
      }).eq('id', selectedProduct.id);
      if (error) throw error;

      setProducts(products.map(p => p.id === selectedProduct.id ? { ...p, price: parseFloat(editPrice), stock_quantity: stock, status } : p));
      setSelectedProduct(null);
    } catch (error) {
      alert('Error', { description: 'Error updating product: ' + (error as any).message, variant: 'danger' });
    } finally { setUpdating(false); }
  };

  const handleDeleteProduct = (id: string, title: string) => {
    confirm(`Delete "${title}"? This cannot be undone.`, async () => {
      try {
        const { error } = await supabase.from('products').delete().eq('id', id);
        if (error) throw error;
        setProducts(products.filter(p => p.id !== id));
        if (selectedProduct?.id === id) setSelectedProduct(null);
      } catch (error) {
        alert('Error', { description: 'Error deleting product: ' + (error as any).message, variant: 'danger' });
      }
    }, { confirmLabel: 'Delete', variant: 'danger' });
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Products</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Monitor listings, edit details, remove items</p>
        </div>
      </div>

      {/* Filters */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '220px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
              placeholder="Search products..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
          </div>
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
            <Filter size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
            <select className="form-control" style={{ width: '140px', padding: '0.45rem' }} value={selectedCategory} onChange={(e) => setSelectedCategory(e.target.value)}>
              <option value="">All Categories</option>
              {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <select className="form-control" style={{ width: '120px', padding: '0.45rem' }} value={selectedStatus} onChange={(e) => setSelectedStatus(e.target.value)}>
              <option value="">All Statuses</option>
              <option value="available">Available</option>
              <option value="reserved">Reserved</option>
              <option value="sold">Sold</option>
            </select>
            <select className="form-control" style={{ width: '120px', padding: '0.45rem' }} value={selectedCondition} onChange={(e) => setSelectedCondition(e.target.value)}>
              <option value="">All Conditions</option>
              <option value="new_">New</option>
              <option value="likeNew">Like New</option>
              <option value="good">Good</option>
              <option value="fair">Fair</option>
              <option value="poor">Poor</option>
            </select>
          </div>
        </div>
      </div>

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
                <th>Product</th>
                <th>Category</th>
                <th>Seller</th>
                <th>Price</th>
                <th>Stock</th>
                <th>Status</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {products.length === 0 ? (
                <tr><td colSpan={7} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))', padding: '2rem' }}>No products found</td></tr>
              ) : (
                products.map((p) => (
                  <tr key={p.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <img src={p.image_urls?.[0] || 'https://placehold.co/100x100?text=No+Image'} alt={p.title}
                          style={{ width: '40px', height: '40px', borderRadius: '4px', border: '1px solid hsl(var(--border))', objectFit: 'cover' }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{p.title}</div>
                          <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))', textTransform: 'capitalize' }}>{p.condition.replace('_', '')}</div>
                        </div>
                      </div>
                    </td>
                    <td><span className="badge badge-info">{p.categories?.name || 'Uncategorized'}</span></td>
                    <td>
                      <div style={{ fontWeight: 500, fontSize: '0.82rem' }}>{p.users?.full_name || 'Unknown'}</div>
                      <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>{p.users?.email}</div>
                    </td>
                    <td style={{ fontWeight: 700, fontSize: '0.85rem' }}>{formatGhs(p.price)}</td>
                    <td>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', fontSize: '0.82rem' }}>
                        <Package size={13} style={{ color: 'hsl(var(--text-tertiary))' }} /> {p.stock_quantity}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${p.status === 'available' ? 'badge-success' : p.status === 'reserved' ? 'badge-warning' : 'badge-danger'}`}>
                        {p.status}
                      </span>
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => openProductDetails(p)}>
                          <Eye size={13} /> View
                        </button>
                        <button className="btn btn-danger btn-sm" onClick={() => handleDeleteProduct(p.id, p.title)}>
                          <Trash2 size={13} />
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

      {/* Product Details Drawer */}
      {selectedProduct && (
        <div className="drawer-backdrop" onClick={() => setSelectedProduct(null)}>
          <div className="drawer" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.875rem' }}>
              <h2 style={{ fontSize: '1.2rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <Tag size={18} style={{ color: 'hsl(var(--accent))' }} /> Product Details
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-secondary))', padding: '4px' }} onClick={() => setSelectedProduct(null)}>
                <X size={20} />
              </button>
            </div>

            {/* Images */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', gap: '0.375rem' }}>
              {selectedProduct.image_urls?.length > 0 ? (
                selectedProduct.image_urls.map((img: string, i: number) => (
                  <img key={i} src={img} alt={`View ${i + 1}`}
                    style={{ width: '100%', height: '80px', borderRadius: '4px', objectFit: 'cover', border: '1px solid hsl(var(--border))' }} />
                ))
              ) : (
                <div style={{ gridColumn: '1/-1', height: '80px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'hsl(var(--bg-surface))', borderRadius: '4px', color: 'hsl(var(--text-tertiary))', fontSize: '0.82rem' }}>
                  No images
                </div>
              )}
            </div>

            <div>
              <h3 style={{ fontSize: '1.1rem', marginBottom: '0.5rem' }}>{selectedProduct.title}</h3>
              <p style={{ color: 'hsl(var(--text-secondary))', fontSize: '0.82rem', lineHeight: 1.5, background: 'hsl(var(--bg-surface))', padding: '0.75rem', borderRadius: 'var(--radius-sm)' }}>
                {selectedProduct.description}
              </p>
            </div>

            {/* Meta */}
            <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', background: 'hsl(var(--bg-surface))' }}>
              {[
                [<><User size={13} /> Seller</>, `${selectedProduct.users?.full_name} (${selectedProduct.users?.email})`],
                [<><MapPin size={13} /> Campus</>, selectedProduct.campus || 'N/A'],
                ['Delivery', `{formatGhs(selectedProduct.delivery_fee)} (${selectedProduct.delivery_option})`],
                ['Listed', new Date(selectedProduct.created_at).toLocaleString()],
              ].map(([label, value], i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                  <span style={{ color: 'hsl(var(--text-tertiary))', display: 'flex', alignItems: 'center', gap: '4px' }}>{label}</span>
                  <span style={{ fontWeight: 500 }}>{value}</span>
                </div>
              ))}
            </div>

            {/* Edit Form */}
            <form onSubmit={handleUpdateProduct} style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
              <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600 }}>Modify Listing</h4>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' }}>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label">Price (GH₵)</label>
                  <input type="number" step="0.01" className="form-control" value={editPrice} onChange={(e) => setEditPrice(e.target.value)} required />
                </div>
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label className="form-label">Stock</label>
                  <input type="number" className="form-control" value={editStock} onChange={(e) => setEditStock(e.target.value)} required />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Status</label>
                <select className="form-control" value={editStatus} onChange={(e) => setEditStatus(e.target.value)}>
                  <option value="available">Available</option>
                  <option value="reserved">Reserved</option>
                  <option value="sold">Sold</option>
                </select>
              </div>
              <div style={{ display: 'flex', gap: '0.625rem', marginTop: '0.5rem' }}>
                <button type="button" className="btn btn-danger"
                  onClick={() => handleDeleteProduct(selectedProduct.id, selectedProduct.title)}>
                  <Trash2 size={14} /> Delete
                </button>
                <button type="submit" className="btn btn-primary" style={{ flex: 1 }} disabled={updating}>
                  {updating ? 'Saving...' : 'Save Changes'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
      {AlertComponent}
      {ConfirmComponent}
    </div>
  );
};
