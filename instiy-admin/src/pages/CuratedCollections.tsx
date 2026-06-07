import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../supabaseClient';
import { uploadToR2 } from '../r2Client';
import {
  Plus, Edit2, Trash2, Loader, X, Upload, GripVertical,
  Eye, EyeOff, Search, Check, LayoutGrid, Rows3, Package, Folder
} from 'lucide-react';

interface CuratedCollection {
  id: string;
  title: string;
  subtitle?: string;
  icon?: string;
  image_url?: string;
  display_mode: 'horizontal' | 'grid';
  content_type: 'products' | 'categories';
  max_items: number;
  is_visible: boolean;
  sort_order: number;
  expires_at?: string;
  created_at: string;
  updated_at: string;
  item_count: number;
}

interface CollectionItem {
  id?: string;
  product_id?: string;
  category_id?: string;
  sort_order: number;
}

interface Product {
  id: string;
  title: string;
  price: number;
  thumbnail_url?: string;
  image_urls?: string[];
  status: string;
}

interface Category {
  id: string;
  name: string;
  image_url?: string;
  icon?: string;
  color_index: number;
}

export const CuratedCollections: React.FC = () => {
  const [collections, setCollections] = useState<CuratedCollection[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingCollection, setEditingCollection] = useState<CuratedCollection | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Form fields
  const [title, setTitle] = useState('');
  const [subtitle, setSubtitle] = useState('');
  const [icon, setIcon] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [displayMode, setDisplayMode] = useState<'horizontal' | 'grid'>('horizontal');
  const [contentType, setContentType] = useState<'products' | 'categories'>('products');
  const [maxItems, setMaxItems] = useState(10);
  const [isVisible, setIsVisible] = useState(true);
  const [sortOrder, setSortOrder] = useState(0);
  const [expiresAt, setExpiresAt] = useState('');

  const formatForDateTimeLocal = (dateStr?: string) => {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return '';
    const pad = (n: number) => n.toString().padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };

  // Items
  const [selectedItems, setSelectedItems] = useState<CollectionItem[]>([]);

  // Picker state
  const [showPicker, setShowPicker] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loadingPicker, setLoadingPicker] = useState(false);

  const [uploadingImage, setUploadingImage] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const fetchCollections = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase.rpc('get_admin_curated_collections');
      if (error) throw error;
      setCollections(data || []);
    } catch (error) {
      console.error('Error fetching collections:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchCollections(); }, []);

  const fetchProducts = async (search: string) => {
    setLoadingPicker(true);
    try {
      let query = supabase
        .from('products')
        .select('id, title, price, thumbnail_url, image_urls, status')
        .eq('status', 'available')
        .order('created_at', { ascending: false })
        .limit(50);
      if (search) query = query.ilike('title', `%${search}%`);
      const { data, error } = await query;
      if (error) throw error;
      setProducts(data || []);
    } catch (err) {
      console.error('Error fetching products:', err);
    } finally {
      setLoadingPicker(false);
    }
  };

  const fetchCategories = async () => {
    setLoadingPicker(true);
    try {
      const { data, error } = await supabase
        .from('categories')
        .select('id, name, image_url, icon, color_index')
        .order('name', { ascending: true });
      if (error) throw error;
      setCategories(data || []);
    } catch (err) {
      console.error('Error fetching categories:', err);
    } finally {
      setLoadingPicker(false);
    }
  };

  const openPicker = () => {
    setShowPicker(true);
    setPickerSearch('');
    if (contentType === 'products') fetchProducts('');
    else fetchCategories();
  };

  const resetForm = () => {
    setTitle(''); setSubtitle(''); setIcon(''); setImageUrl('');
    setDisplayMode('horizontal'); setContentType('products');
    setMaxItems(10); setIsVisible(true); setSortOrder(0);
    setExpiresAt('');
    setSelectedItems([]); setEditingCollection(null);
  };

  const openCreate = () => { resetForm(); setShowModal(true); };

  const openEdit = async (collection: CuratedCollection) => {
    setEditingCollection(collection);
    setTitle(collection.title);
    setSubtitle(collection.subtitle || '');
    setIcon(collection.icon || '');
    setImageUrl(collection.image_url || '');
    setDisplayMode(collection.display_mode);
    setContentType(collection.content_type);
    setMaxItems(collection.max_items);
    setIsVisible(collection.is_visible);
    setSortOrder(collection.sort_order);
    setExpiresAt(collection.expires_at ? formatForDateTimeLocal(collection.expires_at) : '');
    try {
      const { data, error } = await supabase
        .from('curated_collection_items')
        .select('id, product_id, category_id, sort_order')
        .eq('collection_id', collection.id)
        .order('sort_order', { ascending: true });
      if (error) throw error;
      setSelectedItems(data || []);
    } catch (err) {
      console.error('Error fetching items:', err);
      setSelectedItems([]);
    }
    setShowModal(true);
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingImage(true);
    try { setImageUrl(await uploadToR2(file, 'curated')); }
    catch (err: any) { alert('Error: ' + err.message); }
    finally { setUploadingImage(false); }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    setSubmitting(true);
    try {
      const collectionData = {
        title: title.trim(),
        subtitle: subtitle.trim() || null,
        icon: icon.trim() || null,
        image_url: imageUrl || null,
        display_mode: displayMode,
        content_type: contentType,
        max_items: maxItems,
        is_visible: isVisible,
        sort_order: sortOrder,
        expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
      };
      let collectionId: string;
      if (editingCollection) {
        const { error } = await supabase.from('curated_collections').update(collectionData).eq('id', editingCollection.id);
        if (error) throw error;
        collectionId = editingCollection.id;
        await supabase.from('curated_collection_items').delete().eq('collection_id', collectionId);
      } else {
        const { data, error } = await supabase.from('curated_collections').insert(collectionData).select('id').single();
        if (error) throw error;
        collectionId = data.id;
      }
      if (selectedItems.length > 0) {
        const itemsToInsert = selectedItems.map((item, index) => ({
          collection_id: collectionId,
          product_id: item.product_id || null,
          category_id: item.category_id || null,
          sort_order: index,
        }));
        const { error } = await supabase.from('curated_collection_items').insert(itemsToInsert);
        if (error) throw error;
      }
      setShowModal(false);
      resetForm();
      fetchCollections();
    } catch (err: any) { alert('Error: ' + err.message); }
    finally { setSubmitting(false); }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Delete this collection?')) return;
    try {
      const { error } = await supabase.from('curated_collections').delete().eq('id', id);
      if (error) throw error;
      fetchCollections();
    } catch (err: any) { alert('Error: ' + err.message); }
  };

  const toggleVisibility = async (collection: CuratedCollection) => {
    try {
      const { error } = await supabase.from('curated_collections').update({ is_visible: !collection.is_visible }).eq('id', collection.id);
      if (error) throw error;
      fetchCollections();
    } catch (err: any) { alert('Error: ' + err.message); }
  };

  const toggleItem = (id: string, type: 'product' | 'category') => {
    setSelectedItems(prev => {
      const existing = prev.find(item => type === 'product' ? item.product_id === id : item.category_id === id);
      if (existing) return prev.filter(item => type === 'product' ? item.product_id !== id : item.category_id !== id);
      return [...prev, { product_id: type === 'product' ? id : undefined, category_id: type === 'category' ? id : undefined, sort_order: prev.length }];
    });
  };

  const removeItem = (index: number) => setSelectedItems(prev => prev.filter((_, i) => i !== index));

  const moveItem = (index: number, direction: 'up' | 'down') => {
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    if (newIndex < 0 || newIndex >= selectedItems.length) return;
    const items = [...selectedItems];
    [items[index], items[newIndex]] = [items[newIndex], items[index]];
    setSelectedItems(items.map((item, i) => ({ ...item, sort_order: i })));
  };

  const getProductThumbnail = (product: Product) => {
    if (product.thumbnail_url) return product.thumbnail_url;
    if (product.image_urls && product.image_urls.length > 0) return product.image_urls[0];
    return null;
  };

  const getGradient = (index: number) => {
    const gradients = [
      'linear-gradient(135deg, #6c47ff, #a78bfa)', 'linear-gradient(135deg, #f59e0b, #fbbf24)',
      'linear-gradient(135deg, #10b981, #34d399)', 'linear-gradient(135deg, #ec4899, #f472b6)',
      'linear-gradient(135deg, #3b82f6, #60a5fa)', 'linear-gradient(135deg, #f97316, #fb923c)',
      'linear-gradient(135deg, #8b5cf6, #a78bfa)', 'linear-gradient(135deg, #6b7280, #9ca3af)',
    ];
    return gradients[index % gradients.length];
  };

  const iconOptions = ['trending_up', 'crown', 'flame', 'star', 'zap', 'sparkles', 'new', 'tag', 'grid'];

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Curated Collections</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.25rem', fontSize: '0.85rem' }}>Manage home screen sections</p>
        </div>
        <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> Add Collection</button>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : collections.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '2.5rem', color: 'hsl(var(--text-tertiary))' }}>
          <LayoutGrid size={40} style={{ margin: '0 auto 0.75rem', display: 'block', opacity: 0.4 }} />
          No collections yet. Click "Add Collection" to start.
        </div>
      ) : (
        <div className="table-container">
          <table className="table">
            <thead>
              <tr>
                <th style={{ width: '50px' }}>Order</th>
                <th>Collection</th>
                <th style={{ width: '100px' }}>Type</th>
                <th style={{ width: '110px' }}>Display</th>
                <th style={{ width: '60px' }}>Items</th>
                <th style={{ width: '70px' }}>Visible</th>
                <th style={{ width: '100px', textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {collections.map(c => (
                <tr key={c.id}>
                  <td style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.8rem' }}>{c.sort_order}</td>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                      {c.image_url && <img src={c.image_url} alt="" style={{ width: '36px', height: '36px', borderRadius: 'var(--radius-sm)', objectFit: 'cover', border: '1px solid hsl(var(--border))' }} />}
                      <div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                          <span style={{ fontWeight: 600, fontSize: '0.9rem' }}>{c.title}</span>
                          {c.expires_at && (
                            new Date(c.expires_at) <= new Date() ? (
                              <span className="badge badge-danger" style={{ fontSize: '0.6rem', padding: '1px 5px' }}>Expired</span>
                            ) : (
                              <span className="badge badge-info" style={{ fontSize: '0.6rem', padding: '1px 5px', opacity: 0.8 }} title={new Date(c.expires_at).toLocaleString()}>
                                Expires: {new Date(c.expires_at).toLocaleDateString()}
                              </span>
                            )
                          )}
                        </div>
                        {c.subtitle && <div style={{ fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>{c.subtitle}</div>}
                      </div>
                    </div>
                  </td>
                  <td>
                    <span className={`badge ${c.content_type === 'products' ? 'badge-info' : 'badge-success'}`}>
                      {c.content_type === 'products' ? <Package size={10} style={{ marginRight: 3 }} /> : <Folder size={10} style={{ marginRight: 3 }} />}
                      {c.content_type}
                    </span>
                  </td>
                  <td>
                    <span className="badge badge-info" style={{ background: 'hsl(var(--accent-dim))', color: 'hsl(var(--accent))' }}>
                      {c.display_mode === 'horizontal' ? <Rows3 size={10} style={{ marginRight: 3 }} /> : <LayoutGrid size={10} style={{ marginRight: 3 }} />}
                      {c.display_mode}
                    </span>
                  </td>
                  <td style={{ fontSize: '0.85rem' }}>{c.item_count}</td>
                  <td>
                    <button
                      onClick={() => toggleVisibility(c)}
                      style={{ background: 'none', border: 'none', cursor: 'pointer', padding: '4px', color: c.is_visible ? 'hsl(var(--success))' : 'hsl(var(--text-tertiary))' }}
                    >
                      {c.is_visible ? <Eye size={16} /> : <EyeOff size={16} />}
                    </button>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <div style={{ display: 'flex', gap: '0.25rem', justifyContent: 'flex-end' }}>
                      <button className="btn btn-secondary btn-sm" onClick={() => openEdit(c)}><Edit2 size={12} /></button>
                      <button className="btn btn-danger btn-sm" onClick={() => handleDelete(c.id)}><Trash2 size={12} /></button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Create/Edit Modal */}
      {showModal && (
        <div className="modal-backdrop">
          <div className="modal-content" style={{ maxWidth: '600px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.625rem', flexShrink: 0 }}>
              <h2 style={{ fontSize: '1.1rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <LayoutGrid size={18} style={{ color: 'hsl(var(--accent))' }} />
                {editingCollection ? 'Edit Collection' : 'New Collection'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => { setShowModal(false); resetForm(); }}><X size={18} /></button>
            </div>

            <form onSubmit={handleSubmit} style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem' }}>
                <div className="form-group">
                  <label className="form-label">Title *</label>
                  <input type="text" className="form-control" value={title} onChange={e => setTitle(e.target.value)} placeholder="e.g., Trending" required />
                </div>
                <div className="form-group">
                  <label className="form-label">Subtitle</label>
                  <input type="text" className="form-control" value={subtitle} onChange={e => setSubtitle(e.target.value)} placeholder="e.g., Hot right now" />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.875rem' }}>
                <div className="form-group">
                  <label className="form-label">Icon</label>
                  <select className="form-control" value={icon} onChange={e => setIcon(e.target.value)}>
                    <option value="">None</option>
                    {iconOptions.map(i => <option key={i} value={i}>{i}</option>)}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Content Type</label>
                  <select className="form-control" value={contentType} onChange={e => { setContentType(e.target.value as any); setSelectedItems([]); }}>
                    <option value="products">Products</option>
                    <option value="categories">Categories</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Display Mode</label>
                  <select className="form-control" value={displayMode} onChange={e => setDisplayMode(e.target.value as any)}>
                    <option value="horizontal">Horizontal Scroll</option>
                    <option value="grid">Grid</option>
                  </select>
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.875rem' }}>
                <div className="form-group">
                  <label className="form-label">Max Items</label>
                  <input type="number" className="form-control" min={1} max={50} value={maxItems} onChange={e => setMaxItems(parseInt(e.target.value) || 10)} />
                </div>
                <div className="form-group">
                  <label className="form-label">Sort Order</label>
                  <input type="number" className="form-control" min={0} value={sortOrder} onChange={e => setSortOrder(parseInt(e.target.value) || 0)} />
                </div>
                <div className="form-group" style={{ display: 'flex', alignItems: 'flex-end', paddingBottom: '1rem' }}>
                  <label style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer', fontSize: '0.85rem' }}>
                    <input type="checkbox" checked={isVisible} onChange={e => setIsVisible(e.target.checked)} style={{ accentColor: 'hsl(var(--accent))' }} />
                    Visible on home
                  </label>
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem', marginBottom: '1rem' }}>
                <div className="form-group">
                  <label className="form-label">Expiry Date & Time (Optional)</label>
                  <input
                    type="datetime-local"
                    className="form-control"
                    value={expiresAt}
                    onChange={e => setExpiresAt(e.target.value)}
                  />
                  <small style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.7rem', marginTop: '0.25rem', display: 'block' }}>
                    Once expired, this collection will be automatically hidden from the mobile application.
                  </small>
                </div>
              </div>

              {/* Image upload */}
              <div className="form-group">
                <label className="form-label">Header Image</label>
                <input type="file" accept="image/*" style={{ display: 'none' }} ref={fileInputRef} onChange={handleImageUpload} />
                {imageUrl ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.875rem', background: 'hsl(var(--bg-surface))', padding: '0.625rem', borderRadius: 'var(--radius-sm)', border: '1px solid hsl(var(--border))' }}>
                    <img src={imageUrl} alt="Preview" style={{ width: '48px', height: '48px', borderRadius: '4px', objectFit: 'cover' }} />
                    <div style={{ flex: 1, minWidth: 0, fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{imageUrl}</div>
                    <button type="button" className="btn btn-danger btn-sm" onClick={() => setImageUrl('')}>Remove</button>
                  </div>
                ) : (
                  <button type="button" className="btn btn-secondary" style={{ width: '100%', borderStyle: 'dashed', borderWidth: '2px', padding: '0.875rem' }}
                    onClick={() => fileInputRef.current?.click()} disabled={uploadingImage}>
                    {uploadingImage ? <><Loader size={16} className="spin" /> Uploading...</> : <><Upload size={16} /> Upload Image</>}
                  </button>
                )}
              </div>

              {/* Items */}
              <div className="form-group">
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.5rem' }}>
                  <label className="form-label" style={{ marginBottom: 0 }}>Items ({selectedItems.length})</label>
                  <button type="button" className="btn btn-secondary btn-sm" onClick={openPicker}>
                    <Plus size={12} /> Add {contentType === 'products' ? 'Products' : 'Categories'}
                  </button>
                </div>

                {selectedItems.length === 0 ? (
                  <div style={{ border: '2px dashed hsl(var(--border))', borderRadius: 'var(--radius-md)', padding: '1.5rem', textAlign: 'center', color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem' }}>
                    No items selected. Click "Add" to select {contentType}.
                  </div>
                ) : (
                  <div style={{ border: '1px solid hsl(var(--border))', borderRadius: 'var(--radius-sm)', maxHeight: '180px', overflowY: 'auto' }}>
                    {selectedItems.map((item, index) => (
                      <div key={index} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', padding: '0.5rem 0.75rem', borderBottom: index < selectedItems.length - 1 ? '1px solid hsl(var(--border-subtle))' : 'none', fontSize: '0.8rem' }}>
                        <GripVertical size={12} style={{ color: 'hsl(var(--text-tertiary))', flexShrink: 0 }} />
                        <span style={{ color: 'hsl(var(--text-tertiary))', width: '20px', textAlign: 'center', flexShrink: 0 }}>{index + 1}</span>
                        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {item.product_id ? `Product: ${item.product_id.slice(0, 8)}...` : `Category: ${item.category_id?.slice(0, 8)}...`}
                        </span>
                        <button type="button" onClick={() => moveItem(index, 'up')} disabled={index === 0}
                          style={{ background: 'none', border: 'none', cursor: index === 0 ? 'default' : 'pointer', color: 'hsl(var(--text-tertiary))', padding: '2px', opacity: index === 0 ? 0.3 : 1 }}>↑</button>
                        <button type="button" onClick={() => moveItem(index, 'down')} disabled={index === selectedItems.length - 1}
                          style={{ background: 'none', border: 'none', cursor: index === selectedItems.length - 1 ? 'default' : 'pointer', color: 'hsl(var(--text-tertiary))', padding: '2px', opacity: index === selectedItems.length - 1 ? 0.3 : 1 }}>↓</button>
                        <button type="button" onClick={() => removeItem(index)}
                          style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--danger))', padding: '2px' }}><X size={12} /></button>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div style={{ display: 'flex', gap: '0.625rem', justifyContent: 'flex-end', marginTop: '1.25rem', paddingTop: '1rem', borderTop: '1px solid hsl(var(--border))', flexShrink: 0 }}>
                <button type="button" className="btn btn-secondary" onClick={() => { setShowModal(false); resetForm(); }} disabled={submitting}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={submitting}>{submitting ? 'Saving...' : (editingCollection ? 'Update' : 'Create')}</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Product/Category Picker Modal */}
      {showPicker && (
        <div className="modal-backdrop" style={{ zIndex: 1100 }}>
          <div className="modal-content" style={{ maxWidth: '560px', display: 'flex', flexDirection: 'column', maxHeight: '80vh', padding: 0 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '1.25rem 1.5rem 0.75rem', borderBottom: '1px solid hsl(var(--border))', flexShrink: 0 }}>
              <h2 style={{ fontSize: '1.1rem', fontFamily: 'var(--font-title)' }}>
                Select {contentType === 'products' ? 'Products' : 'Categories'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => setShowPicker(false)}><X size={18} /></button>
            </div>

            <div style={{ padding: '0.75rem 1.5rem', flexShrink: 0 }}>
              {contentType === 'products' && (
                <div style={{ position: 'relative', marginBottom: '0.5rem' }}>
                  <Search size={14} style={{ position: 'absolute', left: '0.7rem', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
                  <input type="text" className="form-control" value={pickerSearch}
                    onChange={e => { setPickerSearch(e.target.value); fetchProducts(e.target.value); }}
                    placeholder="Search products..." style={{ paddingLeft: '2rem' }} />
                </div>
              )}
              <div style={{ fontSize: '0.8rem', color: 'hsl(var(--text-tertiary))' }}>{selectedItems.length} selected</div>
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '0 1.5rem', minHeight: 0 }}>
              {loadingPicker ? (
                <div style={{ display: 'flex', justifyContent: 'center', padding: '2rem' }}>
                  <Loader className="spin" size={24} style={{ color: 'hsl(var(--accent))' }} />
                </div>
              ) : contentType === 'products' ? (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                  {products.map(product => {
                    const isSelected = selectedItems.some(i => i.product_id === product.id);
                    const thumb = getProductThumbnail(product);
                    return (
                      <button key={product.id} type="button" onClick={() => toggleItem(product.id, 'product')}
                        style={{
                          display: 'flex', alignItems: 'center', gap: '0.625rem', padding: '0.625rem',
                          background: isSelected ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-surface))',
                          border: `1.5px solid ${isSelected ? 'hsl(var(--accent))' : 'hsl(var(--border))'}`,
                          borderRadius: 'var(--radius-sm)', cursor: 'pointer', textAlign: 'left',
                          transition: 'border-color 150ms, background 150ms',
                        }}>
                        {thumb ? (
                          <img src={thumb} alt="" style={{ width: '40px', height: '40px', borderRadius: '4px', objectFit: 'cover', flexShrink: 0 }} />
                        ) : (
                          <div style={{ width: '40px', height: '40px', borderRadius: '4px', background: 'hsl(var(--bg-card))', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                            <Package size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
                          </div>
                        )}
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <div style={{ fontSize: '0.8rem', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{product.title}</div>
                          <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>GH₵{product.price.toFixed(2)}</div>
                        </div>
                        {isSelected && <Check size={14} style={{ color: 'hsl(var(--accent))', flexShrink: 0 }} />}
                      </button>
                    );
                  })}
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                  {categories.map(category => {
                    const isSelected = selectedItems.some(i => i.category_id === category.id);
                    return (
                      <button key={category.id} type="button" onClick={() => toggleItem(category.id, 'category')}
                        style={{
                          display: 'flex', alignItems: 'center', gap: '0.625rem', padding: '0.625rem',
                          background: isSelected ? 'hsl(var(--accent-dim))' : 'hsl(var(--bg-surface))',
                          border: `1.5px solid ${isSelected ? 'hsl(var(--accent))' : 'hsl(var(--border))'}`,
                          borderRadius: 'var(--radius-sm)', cursor: 'pointer', textAlign: 'left',
                          transition: 'border-color 150ms, background 150ms',
                        }}>
                        {category.image_url ? (
                          <img src={category.image_url} alt="" style={{ width: '40px', height: '40px', borderRadius: '4px', objectFit: 'cover', flexShrink: 0 }} />
                        ) : (
                          <div style={{ width: '40px', height: '40px', borderRadius: '4px', background: getGradient(category.color_index), display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700, fontSize: '0.7rem', textTransform: 'uppercase', flexShrink: 0 }}>
                            {category.name.substring(0, 2)}
                          </div>
                        )}
                        <div style={{ flex: 1, minWidth: 0, fontSize: '0.8rem', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{category.name}</div>
                        {isSelected && <Check size={14} style={{ color: 'hsl(var(--accent))', flexShrink: 0 }} />}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>

            <div style={{ padding: '0.75rem 1.5rem 1.25rem', borderTop: '1px solid hsl(var(--border))', flexShrink: 0 }}>
              <button className="btn btn-primary" style={{ width: '100%' }} onClick={() => setShowPicker(false)}>
                Done ({selectedItems.length} selected)
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
