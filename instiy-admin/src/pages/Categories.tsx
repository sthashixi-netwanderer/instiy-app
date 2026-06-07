import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../supabaseClient';
import { uploadToR2 } from '../r2Client';
import { Plus, Edit2, Trash2, FolderPlus, Loader, Folder, X, Upload, Search } from 'lucide-react';

interface Category {
  id: string;
  name: string;
  slug?: string;
  type?: 'product' | 'service';
  image_url?: string;
  icon: string;
  color_index: number;
  created_at: string;
}

export const Categories: React.FC = () => {
  const [categories, setCategories] = useState<Category[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingCategory, setEditingCategory] = useState<Category | null>(null);
  const [name, setName] = useState('');
  const [slug, setSlug] = useState('');
  const [type, setType] = useState<'product' | 'service'>('product');
  const [imageUrl, setImageUrl] = useState('');
  const [uploadingImage, setUploadingImage] = useState(false);
  const [icon, setIcon] = useState('grid');
  const [colorIndex, setColorIndex] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const fetchCategories = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase.from('categories').select('*').order('name', { ascending: true });
      if (error) throw error;
      setCategories(data || []);
    } catch (error) {
      console.error('Error fetching categories:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchCategories(); }, []);

  const handleImportCSV = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = async (event) => {
      const text = event.target?.result as string;
      if (!text) return;
      const lines = text.split(/\r?\n/);
      const toInsert: any[] = [];
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue;
        const parts = line.split(',');
        if (parts.length >= 2) {
          const id = parts[0].trim();
          const catName = parts[1].trim();
          const catSlug = parts[2] ? parts[2].trim() : catName.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
          const catType = parts[3]?.trim() === 'service' ? 'service' : 'product';
          const ci = i % 8;
          let ic = 'grid';
          const lower = catName.toLowerCase();
          if (lower.includes('music')) ic = 'music';
          else if (lower.includes('book') || lower.includes('tutor') || lower.includes('academic')) ic = 'book';
          else if (lower.includes('furniture')) ic = 'armchair';
          else if (lower.includes('clothing') || lower.includes('wear') || lower.includes('fashion')) ic = 'shirt';
          else if (lower.includes('sport') || lower.includes('rec')) ic = 'dumbbell';
          else if (lower.includes('game') || lower.includes('toy')) ic = 'gamepad';
          else if (lower.includes('edit') || lower.includes('video') || lower.includes('media')) ic = 'video';
          else if (lower.includes('web') || lower.includes('program') || lower.includes('data')) ic = 'code';
          else if (lower.includes('food') || lower.includes('bev')) ic = 'coffee';
          else if (lower.includes('clean') || lower.includes('tool') || lower.includes('hardw')) ic = 'wrench';
          else if (lower.includes('house') || lower.includes('hostel') || lower.includes('home')) ic = 'home';
          else if (lower.includes('car') || lower.includes('vehic')) ic = 'car';
          toInsert.push({ id, name: catName, slug: catSlug, type: catType, icon: ic, color_index: ci, created_at: parts[4] ? new Date(parts[4].trim()).toISOString() : new Date().toISOString() });
        }
      }
      if (toInsert.length === 0) { alert('No valid categories found.'); return; }
      setLoading(true);
      try {
        const { error } = await supabase.from('categories').upsert(toInsert, { onConflict: 'name' });
        if (error) throw error;
        alert(`Imported ${toInsert.length} categories.`);
        fetchCategories();
      } catch (err: any) { alert('Error: ' + err.message); } finally { setLoading(false); }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleNameChange = (val: string) => {
    setName(val);
    if (!editingCategory) setSlug(val.toLowerCase().replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').trim());
  };

  const handleImageFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingImage(true);
    try { setImageUrl(await uploadToR2(file, 'categories')); }
    catch (err: any) { alert('Error: ' + err.message); }
    finally { setUploadingImage(false); }
  };

  const openAddModal = () => { setEditingCategory(null); setName(''); setSlug(''); setType('product'); setImageUrl(''); setIcon('grid'); setColorIndex(0); setShowModal(true); };
  const openEditModal = (cat: Category) => { setEditingCategory(cat); setName(cat.name); setSlug(cat.slug || ''); setType(cat.type || 'product'); setImageUrl(cat.image_url || ''); setIcon(cat.icon || 'grid'); setColorIndex(cat.color_index || 0); setShowModal(true); };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    setSubmitting(true);
    const payload = { name: name.trim(), slug: slug.trim() || name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''), type, image_url: imageUrl || null, icon: icon.trim(), color_index: Number(colorIndex) };
    try {
      if (editingCategory) {
        const { error } = await supabase.from('categories').update(payload).eq('id', editingCategory.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('categories').insert(payload);
        if (error) throw error;
      }
      setShowModal(false);
      fetchCategories();
    } catch (error) { alert('Error: ' + (error as any).message); } finally { setSubmitting(false); }
  };

  const handleDelete = async (id: string, catName: string) => {
    if (!window.confirm(`Delete "${catName}"? Products in this category will lose their reference.`)) return;
    try {
      const { error } = await supabase.from('categories').delete().eq('id', id);
      if (error) throw error;
      setCategories(categories.filter(c => c.id !== id));
    } catch (error) { alert('Error: ' + (error as any).message); }
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

  const filteredCategories = categories.filter(cat => 
    cat.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    (cat.slug && cat.slug.toLowerCase().includes(searchQuery.toLowerCase())) ||
    (cat.type && cat.type.toLowerCase().includes(searchQuery.toLowerCase()))
  );

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Categories</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.25rem', fontSize: '0.85rem' }}>Manage product catalog categories</p>
        </div>
        <div style={{ display: 'flex', gap: '0.625rem' }}>
          <input type="file" accept=".csv" style={{ display: 'none' }} id="csv-file-input" onChange={handleImportCSV} />
          <label htmlFor="csv-file-input" className="btn btn-secondary" style={{ cursor: 'pointer' }}>Import CSV</label>
          <button className="btn btn-primary" onClick={openAddModal}><Plus size={16} /> Add Category</button>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '220px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
              placeholder="Search by category name, slug, or type..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
          </div>
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '1rem' }}>
          {filteredCategories.length === 0 ? (
            <div className="card" style={{ gridColumn: '1 / -1', textAlign: 'center', padding: '2.5rem', color: 'hsl(var(--text-tertiary))' }}>
              <Folder size={40} style={{ margin: '0 auto 0.75rem', display: 'block', opacity: 0.4 }} />
              {searchQuery ? 'No matching categories found.' : 'No categories yet. Click "Add Category" to start.'}
            </div>
          ) : filteredCategories.map((cat) => (
            <div className="card" key={cat.id} style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.875rem' }}>
                {cat.image_url ? (
                  <img src={cat.image_url} alt={cat.name}
                    style={{ width: '48px', height: '48px', borderRadius: 'var(--radius-sm)', objectFit: 'cover', border: '1px solid hsl(var(--border))' }} />
                ) : (
                  <div style={{
                    width: '48px', height: '48px', borderRadius: 'var(--radius-sm)', background: getGradient(cat.color_index),
                    display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 700, fontSize: '0.9rem', textTransform: 'uppercase'
                  }}>{cat.name.substring(0, 2)}</div>
                )}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', marginBottom: '0.125rem' }}>
                    <h3 style={{ fontSize: '1rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{cat.name}</h3>
                    <span className={`badge ${cat.type === 'service' ? 'badge-success' : 'badge-info'}`} style={{ fontSize: '0.6rem', padding: '1px 5px' }}>{cat.type || 'product'}</span>
                  </div>
                  <p style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    <code>{cat.slug || '-'}</code>
                  </p>
                </div>
              </div>
              <div style={{ display: 'flex', gap: '0.375rem', marginTop: 'auto', paddingTop: '0.625rem', borderTop: '1px solid hsl(var(--border))' }}>
                <button className="btn btn-secondary btn-sm" style={{ flex: 1 }} onClick={() => openEditModal(cat)}><Edit2 size={12} /> Edit</button>
                <button className="btn btn-danger btn-sm" style={{ flex: '0 0 auto' }} onClick={() => handleDelete(cat.id, cat.name)} disabled={cat.name === 'Other'}><Trash2 size={12} /></button>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Modal */}
      {showModal && (
        <div className="modal-backdrop">
          <div className="modal-content" style={{ maxWidth: '480px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.625rem' }}>
              <h2 style={{ fontSize: '1.1rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <FolderPlus size={18} style={{ color: 'hsl(var(--accent))' }} />
                {editingCategory ? 'Edit Category' : 'Add Category'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => setShowModal(false)}><X size={18} /></button>
            </div>
            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label className="form-label">Name</label>
                <input type="text" className="form-control" placeholder="e.g. Video Editing" value={name} onChange={(e) => handleNameChange(e.target.value)} required />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem' }}>
                <div className="form-group">
                  <label className="form-label">Slug</label>
                  <input type="text" className="form-control" placeholder="video-editing" value={slug} onChange={(e) => setSlug(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Type</label>
                  <select className="form-control" value={type} onChange={(e) => setType(e.target.value as any)}>
                    <option value="product">Product</option>
                    <option value="service">Service</option>
                  </select>
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Image</label>
                <input type="file" accept="image/*" style={{ display: 'none' }} ref={fileInputRef} onChange={handleImageFileChange} />
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
              <div style={{ display: 'flex', gap: '0.625rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setShowModal(false)} disabled={submitting}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={submitting || uploadingImage}>{submitting ? 'Saving...' : 'Save'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
