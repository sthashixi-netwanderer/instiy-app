import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../supabaseClient';
import { uploadToR2 } from '../r2Client';
import {
  Plus, Edit2, Trash2, Loader, X, Upload,
  Eye, EyeOff, Search, Check, Image, Film, FileImage,
  Type, Link, ExternalLink, Package, Folder
} from 'lucide-react';

interface CarouselSlide {
  id: string;
  media_url: string;
  media_type: 'image' | 'video' | 'gif';
  thumbnail_url?: string;
  title?: string;
  subtitle?: string;
  button_text?: string;
  button_link_type?: 'product' | 'category' | 'url';
  button_link_value?: string;
  is_visible: boolean;
  sort_order: number;
  created_at: string;
  updated_at: string;
  linked_product_title?: string;
  linked_category_name?: string;
}

interface Product {
  id: string;
  title: string;
  price: number;
  thumbnail_url?: string;
  image_urls?: string[];
}

interface Category {
  id: string;
  name: string;
  image_url?: string;
  icon?: string;
}

export const Carousel: React.FC = () => {
  const [slides, setSlides] = useState<CarouselSlide[]>([]);
  const [loading, setLoading] = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [editingSlide, setEditingSlide] = useState<CarouselSlide | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Form fields
  const [mediaUrl, setMediaUrl] = useState('');
  const [mediaType, setMediaType] = useState<'image' | 'video' | 'gif'>('image');
  const [thumbnailUrl, setThumbnailUrl] = useState('');
  const [title, setTitle] = useState('');
  const [subtitle, setSubtitle] = useState('');
  const [buttonText, setButtonText] = useState('');
  const [buttonLinkType, setButtonLinkType] = useState<'product' | 'category' | 'url' | ''>('');
  const [buttonLinkValue, setButtonLinkValue] = useState('');
  const [isVisible, setIsVisible] = useState(true);
  const [sortOrder, setSortOrder] = useState(0);

  // Upload state
  const [uploadingMedia, setUploadingMedia] = useState(false);
  const [uploadingThumbnail, setUploadingThumbnail] = useState(false);
  const [batchUploading, setBatchUploading] = useState(false);
  const [batchProgress, setBatchProgress] = useState({ done: 0, total: 0 });
  const mediaInputRef = useRef<HTMLInputElement>(null);
  const thumbnailInputRef = useRef<HTMLInputElement>(null);
  const multiUploadRef = useRef<HTMLInputElement>(null);

  // Picker state for product/category selection
  const [showPicker, setShowPicker] = useState(false);
  const [pickerSearch, setPickerSearch] = useState('');
  const [products, setProducts] = useState<Product[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [loadingPicker, setLoadingPicker] = useState(false);

  const fetchSlides = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase.rpc('get_admin_carousel_slides');
      if (error) throw error;
      setSlides(data || []);
    } catch (error) {
      console.error('Error fetching carousel slides:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchSlides(); }, []);

  const fetchProducts = async (search: string) => {
    setLoadingPicker(true);
    try {
      let query = supabase
        .from('products')
        .select('id, title, price, thumbnail_url, image_urls')
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
        .select('id, name, image_url, icon')
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
    if (buttonLinkType === 'product') fetchProducts('');
    else fetchCategories();
  };

  const resetForm = () => {
    setMediaUrl(''); setMediaType('image'); setThumbnailUrl('');
    setTitle(''); setSubtitle(''); setButtonText('');
    setButtonLinkType(''); setButtonLinkValue('');
    setIsVisible(true); setSortOrder(0);
    setEditingSlide(null);
  };

  const openCreate = () => { resetForm(); setShowModal(true); };

  const openEdit = (slide: CarouselSlide) => {
    setEditingSlide(slide);
    setMediaUrl(slide.media_url);
    setMediaType(slide.media_type);
    setThumbnailUrl(slide.thumbnail_url || '');
    setTitle(slide.title || '');
    setSubtitle(slide.subtitle || '');
    setButtonText(slide.button_text || '');
    setButtonLinkType(slide.button_link_type || '');
    setButtonLinkValue(slide.button_link_value || '');
    setIsVisible(slide.is_visible);
    setSortOrder(slide.sort_order);
    setShowModal(true);
  };

  const handleMediaUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingMedia(true);
    try {
      const url = await uploadToR2(file, 'carousel');
      setMediaUrl(url);
      // Auto-detect media type
      if (file.type.startsWith('video/')) setMediaType('video');
      else if (file.type === 'image/gif') setMediaType('gif');
      else setMediaType('image');
    } catch (err: any) { alert('Error: ' + err.message); }
    finally { setUploadingMedia(false); }
  };

  const handleThumbnailUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingThumbnail(true);
    try { setThumbnailUrl(await uploadToR2(file, 'carousel/thumbnails')); }
    catch (err: any) { alert('Error: ' + err.message); }
    finally { setUploadingThumbnail(false); }
  };

  const detectMediaType = (file: File): 'image' | 'video' | 'gif' => {
    if (file.type.startsWith('video/')) return 'video';
    if (file.type === 'image/gif') return 'gif';
    return 'image';
  };

  const handleMultiUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    if (files.length === 0) return;

    setBatchUploading(true);
    setBatchProgress({ done: 0, total: files.length });

    const errors: string[] = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      try {
        const url = await uploadToR2(file, 'carousel');
        const type = detectMediaType(file);
        const maxOrder = slides.length > 0 ? Math.max(...slides.map(s => s.sort_order)) : -1;
        const { error } = await supabase.from('carousel_slides').insert({
          media_url: url,
          media_type: type,
          is_visible: true,
          sort_order: maxOrder + i + 1,
        });
        if (error) throw error;
      } catch (err: any) {
        errors.push(`${file.name}: ${err.message}`);
      }
      setBatchProgress(prev => ({ ...prev, done: i + 1 }));
    }

    setBatchUploading(false);
    setBatchProgress({ done: 0, total: 0 });
    if (multiUploadRef.current) multiUploadRef.current.value = '';

    if (errors.length > 0) {
      alert(`Uploaded ${files.length - errors.length}/${files.length} files.\n\nFailed:\n${errors.join('\n')}`);
    }
    fetchSlides();
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!mediaUrl.trim()) return;
    setSubmitting(true);
    try {
      const slideData = {
        media_url: mediaUrl.trim(),
        media_type: mediaType,
        thumbnail_url: thumbnailUrl.trim() || null,
        title: title.trim() || null,
        subtitle: subtitle.trim() || null,
        button_text: buttonText.trim() || null,
        button_link_type: buttonLinkType || null,
        button_link_value: buttonLinkValue.trim() || null,
        is_visible: isVisible,
        sort_order: sortOrder,
      };
      if (editingSlide) {
        const { error } = await supabase.from('carousel_slides').update(slideData).eq('id', editingSlide.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('carousel_slides').insert(slideData);
        if (error) throw error;
      }
      setShowModal(false);
      resetForm();
      fetchSlides();
    } catch (err: any) { alert('Error: ' + err.message); }
    finally { setSubmitting(false); }
  };

  const handleDelete = async (id: string) => {
    if (!window.confirm('Delete this carousel slide?')) return;
    try {
      const { error } = await supabase.from('carousel_slides').delete().eq('id', id);
      if (error) throw error;
      fetchSlides();
    } catch (err: any) { alert('Error: ' + err.message); }
  };

  const toggleVisibility = async (slide: CarouselSlide) => {
    try {
      const { error } = await supabase.from('carousel_slides').update({ is_visible: !slide.is_visible }).eq('id', slide.id);
      if (error) throw error;
      fetchSlides();
    } catch (err: any) { alert('Error: ' + err.message); }
  };

  const moveSlide = async (index: number, direction: 'up' | 'down') => {
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    if (newIndex < 0 || newIndex >= slides.length) return;
    const updated = [...slides];
    const tempOrder = updated[index].sort_order;
    updated[index] = { ...updated[index], sort_order: updated[newIndex].sort_order };
    updated[newIndex] = { ...updated[newIndex], sort_order: tempOrder };
    try {
      await supabase.from('carousel_slides').update({ sort_order: updated[index].sort_order }).eq('id', updated[index].id);
      await supabase.from('carousel_slides').update({ sort_order: updated[newIndex].sort_order }).eq('id', updated[newIndex].id);
      fetchSlides();
    } catch (err: any) { alert('Error: ' + err.message); }
  };

  const selectProduct = (product: Product) => {
    setButtonLinkValue(product.id);
    setShowPicker(false);
  };

  const selectCategory = (category: Category) => {
    setButtonLinkValue(category.id);
    setShowPicker(false);
  };

  const getMediaIcon = (type: string) => {
    switch (type) {
      case 'video': return <Film size={14} />;
      case 'gif': return <FileImage size={14} />;
      default: return <Image size={14} />;
    }
  };

  const getLinkLabel = (slide: CarouselSlide) => {
    if (!slide.button_link_type) return null;
    switch (slide.button_link_type) {
      case 'product': return slide.linked_product_title || `Product: ${slide.button_link_value?.slice(0, 8)}...`;
      case 'category': return slide.linked_category_name || `Category: ${slide.button_link_value?.slice(0, 8)}...`;
      case 'url': return slide.button_link_value;
      default: return null;
    }
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Home Carousel</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.25rem', fontSize: '0.85rem' }}>Manage home screen carousel slides</p>
        </div>
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
          {batchUploading && (
            <span style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))' }}>
              Uploading {batchProgress.done}/{batchProgress.total}...
            </span>
          )}
          <input type="file" accept="image/*,video/*,.gif" multiple style={{ display: 'none' }} ref={multiUploadRef} onChange={handleMultiUpload} />
          <button className="btn btn-secondary" onClick={() => multiUploadRef.current?.click()} disabled={batchUploading}>
            {batchUploading ? <><Loader size={16} className="spin" /> Uploading...</> : <><Upload size={16} /> Quick Upload</>}
          </button>
          <button className="btn btn-primary" onClick={openCreate}><Plus size={16} /> Add Slide</button>
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : slides.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '2.5rem', color: 'hsl(var(--text-tertiary))' }}>
          <Image size={40} style={{ margin: '0 auto 0.75rem', display: 'block', opacity: 0.4 }} />
          No carousel slides yet. Click "Quick Upload" to upload multiple files at once, or "Add Slide" for one at a time.
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: '1rem' }}>
          {slides.map((slide, index) => (
            <div key={slide.id} className="card" style={{ padding: 0, overflow: 'hidden', opacity: slide.is_visible ? 1 : 0.6 }}>
              {/* Media preview */}
              <div style={{ position: 'relative', height: '180px', background: 'hsl(var(--bg-surface))' }}>
                {slide.media_type === 'video' ? (
                  <video
                    src={slide.media_url}
                    style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    muted
                    loop
                    onMouseEnter={e => (e.target as HTMLVideoElement).play()}
                    onMouseLeave={e => { (e.target as HTMLVideoElement).pause(); (e.target as HTMLVideoElement).currentTime = 0; }}
                  />
                ) : (
                  <img src={slide.media_url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                )}
                {/* Media type badge */}
                <div style={{
                  position: 'absolute', top: '8px', left: '8px',
                  display: 'flex', alignItems: 'center', gap: '4px',
                  padding: '3px 8px', borderRadius: '6px',
                  background: 'rgba(0,0,0,0.6)', color: 'white', fontSize: '0.7rem', fontWeight: 600,
                }}>
                  {getMediaIcon(slide.media_type)}
                  {slide.media_type.toUpperCase()}
                </div>
                {/* Visibility toggle */}
                <button
                  onClick={() => toggleVisibility(slide)}
                  style={{
                    position: 'absolute', top: '8px', right: '8px',
                    background: 'rgba(0,0,0,0.5)', border: 'none', cursor: 'pointer',
                    padding: '6px', borderRadius: '6px',
                    color: slide.is_visible ? '#4ade80' : '#9ca3af',
                  }}
                >
                  {slide.is_visible ? <Eye size={14} /> : <EyeOff size={14} />}
                </button>
              </div>

              {/* Slide info */}
              <div style={{ padding: '0.875rem' }}>
                {slide.title && (
                  <div style={{ fontWeight: 600, fontSize: '0.9rem', marginBottom: '0.25rem' }}>{slide.title}</div>
                )}
                {slide.subtitle && (
                  <div style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.5rem' }}>{slide.subtitle}</div>
                )}
                {slide.button_text && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', fontSize: '0.75rem', color: 'hsl(var(--accent))', marginBottom: '0.5rem' }}>
                    <Link size={11} />
                    {slide.button_text}
                    {slide.button_link_type && (
                      <span style={{ color: 'hsl(var(--text-tertiary))' }}>
                        &rarr; {getLinkLabel(slide)}
                      </span>
                    )}
                  </div>
                )}
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: '0.5rem' }}>
                  <div style={{ display: 'flex', gap: '0.25rem' }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => moveSlide(index, 'up')} disabled={index === 0}
                      style={{ opacity: index === 0 ? 0.3 : 1 }}>&uarr;</button>
                    <button className="btn btn-secondary btn-sm" onClick={() => moveSlide(index, 'down')} disabled={index === slides.length - 1}
                      style={{ opacity: index === slides.length - 1 ? 0.3 : 1 }}>&darr;</button>
                  </div>
                  <div style={{ display: 'flex', gap: '0.25rem' }}>
                    <button className="btn btn-secondary btn-sm" onClick={() => openEdit(slide)}><Edit2 size={12} /></button>
                    <button className="btn btn-danger btn-sm" onClick={() => handleDelete(slide.id)}><Trash2 size={12} /></button>
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Create/Edit Modal */}
      {showModal && (
        <div className="modal-backdrop">
          <div className="modal-content" style={{ maxWidth: '640px', display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.625rem', flexShrink: 0 }}>
              <h2 style={{ fontSize: '1.1rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <Image size={18} style={{ color: 'hsl(var(--accent))' }} />
                {editingSlide ? 'Edit Slide' : 'New Slide'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => { setShowModal(false); resetForm(); }}><X size={18} /></button>
            </div>

            <form onSubmit={handleSubmit} style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
              {/* Media upload */}
              <div className="form-group">
                <label className="form-label">Media *</label>
                <input type="file" accept="image/*,video/*,.gif" style={{ display: 'none' }} ref={mediaInputRef} onChange={handleMediaUpload} />
                {mediaUrl ? (
                  <div style={{ position: 'relative', borderRadius: 'var(--radius-sm)', overflow: 'hidden', border: '1px solid hsl(var(--border))' }}>
                    {mediaType === 'video' ? (
                      <video src={mediaUrl} style={{ width: '100%', height: '200px', objectFit: 'cover' }} controls muted />
                    ) : (
                      <img src={mediaUrl} alt="Preview" style={{ width: '100%', height: '200px', objectFit: 'cover' }} />
                    )}
                    <div style={{ position: 'absolute', top: '8px', right: '8px', display: 'flex', gap: '4px' }}>
                      <button type="button" className="btn btn-secondary btn-sm" onClick={() => mediaInputRef.current?.click()}>Replace</button>
                      <button type="button" className="btn btn-danger btn-sm" onClick={() => { setMediaUrl(''); setMediaType('image'); }}>Remove</button>
                    </div>
                    <div style={{ position: 'absolute', bottom: '8px', left: '8px', display: 'flex', gap: '6px' }}>
                      {(['image', 'video', 'gif'] as const).map(t => (
                        <button key={t} type="button" onClick={() => setMediaType(t)}
                          style={{
                            padding: '3px 10px', borderRadius: '6px', border: 'none', cursor: 'pointer',
                            fontSize: '0.7rem', fontWeight: 600, textTransform: 'uppercase',
                            background: mediaType === t ? 'hsl(var(--accent))' : 'rgba(0,0,0,0.5)',
                            color: 'white',
                          }}>
                          {t}
                        </button>
                      ))}
                    </div>
                  </div>
                ) : (
                  <button type="button" className="btn btn-secondary" style={{ width: '100%', borderStyle: 'dashed', borderWidth: '2px', padding: '2rem' }}
                    onClick={() => mediaInputRef.current?.click()} disabled={uploadingMedia}>
                    {uploadingMedia ? <><Loader size={16} className="spin" /> Uploading...</> : <><Upload size={16} /> Upload Image, Video, or GIF</>}
                  </button>
                )}
                <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))', marginTop: '0.375rem' }}>
                  Videos are muted by default. Max video length: 10 seconds.
                </div>
              </div>

              {/* Thumbnail (for videos) */}
              {mediaType === 'video' && (
                <div className="form-group">
                  <label className="form-label">Video Thumbnail (optional)</label>
                  <input type="file" accept="image/*" style={{ display: 'none' }} ref={thumbnailInputRef} onChange={handleThumbnailUpload} />
                  {thumbnailUrl ? (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', background: 'hsl(var(--bg-surface))', padding: '0.5rem', borderRadius: 'var(--radius-sm)', border: '1px solid hsl(var(--border))' }}>
                      <img src={thumbnailUrl} alt="" style={{ width: '48px', height: '48px', borderRadius: '4px', objectFit: 'cover' }} />
                      <button type="button" className="btn btn-danger btn-sm" onClick={() => setThumbnailUrl('')}>Remove</button>
                    </div>
                  ) : (
                    <button type="button" className="btn btn-secondary btn-sm" onClick={() => thumbnailInputRef.current?.click()} disabled={uploadingThumbnail}>
                      {uploadingThumbnail ? <><Loader size={12} className="spin" /> Uploading...</> : <><Upload size={12} /> Upload Thumbnail</>}
                    </button>
                  )}
                </div>
              )}

              {/* Text overlay */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem' }}>
                <div className="form-group">
                  <label className="form-label"><Type size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} /> Title Overlay</label>
                  <input type="text" className="form-control" value={title} onChange={e => setTitle(e.target.value)} placeholder="e.g., Summer Sale" />
                </div>
                <div className="form-group">
                  <label className="form-label">Subtitle Overlay</label>
                  <input type="text" className="form-control" value={subtitle} onChange={e => setSubtitle(e.target.value)} placeholder="e.g., Up to 50% off" />
                </div>
              </div>

              {/* Button config */}
              <div style={{ background: 'hsl(var(--bg-surface))', borderRadius: 'var(--radius-md)', padding: '1rem', border: '1px solid hsl(var(--border))', marginBottom: '1rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.875rem', fontWeight: 600, fontSize: '0.9rem' }}>
                  <Link size={14} style={{ color: 'hsl(var(--accent))' }} />
                  Call-to-Action Button
                </div>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem' }}>
                  <div className="form-group">
                    <label className="form-label">Button Text</label>
                    <input type="text" className="form-control" value={buttonText} onChange={e => setButtonText(e.target.value)} placeholder="e.g., Shop Now" />
                  </div>
                  <div className="form-group">
                    <label className="form-label">Link Type</label>
                    <select className="form-control" value={buttonLinkType} onChange={e => { setButtonLinkType(e.target.value as any); setButtonLinkValue(''); }}>
                      <option value="">No button</option>
                      <option value="product">Product</option>
                      <option value="category">Category</option>
                      <option value="url">External URL</option>
                    </select>
                  </div>
                </div>

                {buttonLinkType === 'url' && (
                  <div className="form-group">
                    <label className="form-label"><ExternalLink size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} /> URL</label>
                    <input type="url" className="form-control" value={buttonLinkValue} onChange={e => setButtonLinkValue(e.target.value)} placeholder="https://..." />
                  </div>
                )}

                {(buttonLinkType === 'product' || buttonLinkType === 'category') && (
                  <div className="form-group">
                    <label className="form-label">
                      {buttonLinkType === 'product' ? <Package size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} /> : <Folder size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} />}
                      Linked {buttonLinkType === 'product' ? 'Product' : 'Category'}
                    </label>
                    {buttonLinkValue ? (
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', background: 'hsl(var(--bg-card))', padding: '0.5rem 0.75rem', borderRadius: 'var(--radius-sm)', border: '1px solid hsl(var(--border))' }}>
                        <Check size={14} style={{ color: 'hsl(var(--success))' }} />
                        <span style={{ flex: 1, fontSize: '0.8rem', fontWeight: 500 }}>
                          {buttonLinkType === 'product'
                            ? (slides.find(s => s.button_link_value === buttonLinkValue)?.linked_product_title || `ID: ${buttonLinkValue.slice(0, 8)}...`)
                            : (slides.find(s => s.button_link_value === buttonLinkValue)?.linked_category_name || `ID: ${buttonLinkValue.slice(0, 8)}...`)}
                        </span>
                        <button type="button" className="btn btn-secondary btn-sm" onClick={() => { setButtonLinkValue(''); openPicker(); }}>Change</button>
                        <button type="button" className="btn btn-danger btn-sm" onClick={() => setButtonLinkValue('')}>Clear</button>
                      </div>
                    ) : (
                      <button type="button" className="btn btn-secondary" style={{ width: '100%', borderStyle: 'dashed' }} onClick={openPicker}>
                        <Search size={14} /> Select {buttonLinkType === 'product' ? 'Product' : 'Category'}
                      </button>
                    )}
                  </div>
                )}
              </div>

              {/* Settings */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.875rem' }}>
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

              <div style={{ display: 'flex', gap: '0.625rem', justifyContent: 'flex-end', marginTop: '1.25rem', paddingTop: '1rem', borderTop: '1px solid hsl(var(--border))', flexShrink: 0 }}>
                <button type="button" className="btn btn-secondary" onClick={() => { setShowModal(false); resetForm(); }} disabled={submitting}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={submitting || !mediaUrl}>{submitting ? 'Saving...' : (editingSlide ? 'Update' : 'Create')}</button>
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
                Select {buttonLinkType === 'product' ? 'Product' : 'Category'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', padding: '4px' }}
                onClick={() => setShowPicker(false)}><X size={18} /></button>
            </div>

            <div style={{ padding: '0.75rem 1.5rem', flexShrink: 0 }}>
              <div style={{ position: 'relative' }}>
                <Search size={14} style={{ position: 'absolute', left: '0.7rem', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
                <input type="text" className="form-control" value={pickerSearch}
                  onChange={e => {
                    setPickerSearch(e.target.value);
                    if (buttonLinkType === 'product') fetchProducts(e.target.value);
                  }}
                  placeholder={`Search ${buttonLinkType === 'product' ? 'products' : 'categories'}...`} style={{ paddingLeft: '2rem' }} />
              </div>
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '0 1.5rem', minHeight: 0 }}>
              {loadingPicker ? (
                <div style={{ display: 'flex', justifyContent: 'center', padding: '2rem' }}>
                  <Loader className="spin" size={24} style={{ color: 'hsl(var(--accent))' }} />
                </div>
              ) : buttonLinkType === 'product' ? (
                <div style={{ display: 'grid', gap: '0.375rem' }}>
                  {products.map(product => {
                    const thumb = product.thumbnail_url || (product.image_urls?.[0]);
                    return (
                      <button key={product.id} type="button" onClick={() => selectProduct(product)}
                        style={{
                          display: 'flex', alignItems: 'center', gap: '0.625rem', padding: '0.625rem',
                          background: 'hsl(var(--bg-surface))', border: '1.5px solid hsl(var(--border))',
                          borderRadius: 'var(--radius-sm)', cursor: 'pointer', textAlign: 'left',
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
                          <div style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))' }}>GH&#8373;{product.price.toFixed(2)}</div>
                        </div>
                      </button>
                    );
                  })}
                  {products.length === 0 && (
                    <div style={{ textAlign: 'center', padding: '2rem', color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem' }}>No products found</div>
                  )}
                </div>
              ) : (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.5rem' }}>
                  {categories.map(category => (
                    <button key={category.id} type="button" onClick={() => selectCategory(category)}
                      style={{
                        display: 'flex', alignItems: 'center', gap: '0.625rem', padding: '0.625rem',
                        background: 'hsl(var(--bg-surface))', border: '1.5px solid hsl(var(--border))',
                        borderRadius: 'var(--radius-sm)', cursor: 'pointer', textAlign: 'left',
                      }}>
                      {category.image_url ? (
                        <img src={category.image_url} alt="" style={{ width: '40px', height: '40px', borderRadius: '4px', objectFit: 'cover', flexShrink: 0 }} />
                      ) : (
                        <div style={{ width: '40px', height: '40px', borderRadius: '4px', background: 'hsl(var(--accent-dim))', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                          <Folder size={14} style={{ color: 'hsl(var(--accent))' }} />
                        </div>
                      )}
                      <div style={{ flex: 1, minWidth: 0, fontSize: '0.8rem', fontWeight: 600, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{category.name}</div>
                    </button>
                  ))}
                  {categories.length === 0 && (
                    <div style={{ textAlign: 'center', padding: '2rem', color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', gridColumn: '1 / -1' }}>No categories found</div>
                  )}
                </div>
              )}
            </div>

            <div style={{ padding: '0.75rem 1.5rem 1.25rem', borderTop: '1px solid hsl(var(--border))', flexShrink: 0 }}>
              <button className="btn btn-secondary" style={{ width: '100%' }} onClick={() => setShowPicker(false)}>Cancel</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
