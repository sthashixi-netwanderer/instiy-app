import React, { useEffect, useState } from 'react';
import { supabase } from '../supabaseClient';
import { Search, Filter, Eye, Trash2, Loader, Briefcase, User, Star, Clock, Building, X, Layers } from 'lucide-react';
import { useAlert, useConfirm } from '../components/use-alert';
import { formatGhs } from '../utils/format';

interface ServicePackage {
  tier: string;
  name: string;
  description: string;
  price: number;
  delivery_days: number;
  revisions: number;
  is_popular: boolean;
}

export const Services: React.FC = () => {
  const [services, setServices] = useState<any[]>([]);
  const [categories, setCategories] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('');
  const [selectedStatus, setSelectedStatus] = useState('');
  const [selectedService, setSelectedService] = useState<any>(null);
  const [editStatus, setEditStatus] = useState('');
  const [updating, setUpdating] = useState(false);
  const { alert, AlertComponent } = useAlert();
  const { confirm, ConfirmComponent } = useConfirm();

  const fetchCategories = async () => {
    try {
      const { data } = await supabase.from('categories').select('id, name').eq('type', 'service').order('name');
      setCategories(data || []);
    } catch (e) { console.error(e); }
  };

  const fetchServices = async () => {
    try {
      setLoading(true);
      let query = supabase
        .from('services')
        .select(`*, provider:users!services_provider_id_fkey ( full_name, email ), category:categories ( name ), packages:service_packages ( tier, name, description, price, delivery_days, revisions, is_popular )`)
        .order('created_at', { ascending: false });

      if (searchQuery.trim()) query = query.or(`title.ilike.%${searchQuery}%,description.ilike.%${searchQuery}%`);
      if (selectedCategory) query = query.eq('category_id', selectedCategory);
      if (selectedStatus) query = query.eq('status', selectedStatus);

      const { data, error } = await query;
      if (error) throw error;
      setServices(data || []);
    } catch (error) {
      console.error('Error fetching services:', error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchCategories(); }, []);
  useEffect(() => { fetchServices(); }, [searchQuery, selectedCategory, selectedStatus]);

  const openServiceDetails = (service: any) => {
    setSelectedService(service);
    setEditStatus(service.status);
  };

  const handleUpdateStatus = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedService) return;
    setUpdating(true);
    try {
      const { error } = await supabase.from('services')
        .update({ status: editStatus, updated_at: new Date().toISOString() })
        .eq('id', selectedService.id);
      if (error) throw error;

      setServices(services.map(s => s.id === selectedService.id ? { ...s, status: editStatus } : s));
      setSelectedService(null);
    } catch (error) {
      alert('Error', { description: 'Error updating service: ' + (error as any).message, variant: 'danger' });
    } finally { setUpdating(false); }
  };

  const handleToggleStatus = async (service: any) => {
    const next = service.status === 'active' ? 'paused' : 'active';
    try {
      const { error } = await supabase.from('services')
        .update({ status: next, updated_at: new Date().toISOString() })
        .eq('id', service.id);
      if (error) throw error;
      setServices(services.map(s => s.id === service.id ? { ...s, status: next } : s));
    } catch (error) {
      alert('Error', { description: 'Error updating service: ' + (error as any).message, variant: 'danger' });
    }
  };

  const handleDeleteService = (id: string, title: string) => {
    confirm(`Delete "${title}"? This cannot be undone.`, async () => {
      try {
        const { error } = await supabase.from('services').delete().eq('id', id);
        if (error) throw error;
        setServices(services.filter(s => s.id !== id));
        if (selectedService?.id === id) setSelectedService(null);
      } catch (error) {
        alert('Error', { description: 'Error deleting service: ' + (error as any).message, variant: 'danger' });
      }
    }, { confirmLabel: 'Delete', variant: 'danger' });
  };

  const sortedPackages = (packages: ServicePackage[] | undefined) => {
    if (!packages) return [];
    const order: Record<string, number> = { basic: 0, standard: 1, premium: 2 };
    return [...packages].sort((a, b) => (order[a.tier] ?? 3) - (order[b.tier] ?? 3));
  };

  const statusBadge = (status: string) =>
    status === 'active' ? 'badge-success' : status === 'paused' ? 'badge-warning' : 'badge-secondary';

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Services</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Manage service marketplace listings</p>
        </div>
      </div>

      {/* Filters */}
      <div className="card" style={{ marginBottom: '1.5rem' }}>
        <div style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: '220px' }}>
            <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
            <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
              placeholder="Search services..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
          </div>
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
            <Filter size={14} style={{ color: 'hsl(var(--text-tertiary))' }} />
            <select className="form-control" style={{ width: '160px', padding: '0.45rem' }} value={selectedCategory} onChange={(e) => setSelectedCategory(e.target.value)}>
              <option value="">All Categories</option>
              {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <select className="form-control" style={{ width: '120px', padding: '0.45rem' }} value={selectedStatus} onChange={(e) => setSelectedStatus(e.target.value)}>
              <option value="">All Statuses</option>
              <option value="active">Active</option>
              <option value="paused">Paused</option>
              <option value="inactive">Inactive</option>
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
                <th>Service</th>
                <th>Category</th>
                <th>Provider</th>
                <th>Price</th>
                <th>Rating</th>
                <th>Status</th>
                <th style={{ textAlign: 'right' }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {services.length === 0 ? (
                <tr><td colSpan={7} style={{ textAlign: 'center', color: 'hsl(var(--text-tertiary))', padding: '2rem' }}>No services found</td></tr>
              ) : (
                services.map((s) => (
                  <tr key={s.id}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.625rem' }}>
                        <img src={s.image_urls?.[0] || 'https://placehold.co/100x100?text=No+Image'} alt={s.title}
                          style={{ width: '40px', height: '40px', borderRadius: '4px', border: '1px solid hsl(var(--border))', objectFit: 'cover' }} />
                        <div>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{s.title}</div>
                          <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))', display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <Layers size={11} /> {s.packages?.length || 0} package{(s.packages?.length || 0) === 1 ? '' : 's'}
                          </div>
                        </div>
                      </div>
                    </td>
                    <td><span className="badge badge-info">{s.category?.name || s.category || 'Uncategorized'}</span></td>
                    <td>
                      <div style={{ fontWeight: 500, fontSize: '0.82rem' }}>{s.provider?.full_name || 'Unknown'}</div>
                      <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))' }}>{s.provider?.email}</div>
                    </td>
                    <td style={{ fontWeight: 700, fontSize: '0.85rem' }}>{formatGhs(s.price)}</td>
                    <td>
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', fontSize: '0.82rem' }}>
                        <Star size={13} style={{ color: '#f59e0b', fill: s.review_count > 0 ? '#f59e0b' : 'none' }} />
                        {Number(s.average_rating || 0).toFixed(1)} ({s.review_count || 0})
                      </span>
                    </td>
                    <td><span className={`badge ${statusBadge(s.status)}`}>{s.status}</span></td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.375rem', justifyContent: 'flex-end' }}>
                        <button className="btn btn-secondary btn-sm" onClick={() => handleToggleStatus(s)}>
                          {s.status === 'active' ? 'Pause' : 'Publish'}
                        </button>
                        <button className="btn btn-secondary btn-sm" onClick={() => openServiceDetails(s)}>
                          <Eye size={13} /> View
                        </button>
                        <button className="btn btn-danger btn-sm" onClick={() => handleDeleteService(s.id, s.title)}>
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

      {/* Service Details Drawer */}
      {selectedService && (
        <div className="drawer-backdrop" onClick={() => setSelectedService(null)}>
          <div className="drawer" onClick={(e) => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.875rem' }}>
              <h2 style={{ fontSize: '1.2rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <Briefcase size={18} style={{ color: 'hsl(var(--accent))' }} /> Service Details
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-secondary))', padding: '4px' }} onClick={() => setSelectedService(null)}>
                <X size={20} />
              </button>
            </div>

            {/* Images */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(100px, 1fr))', gap: '0.375rem' }}>
              {selectedService.image_urls?.length > 0 ? (
                selectedService.image_urls.map((img: string, i: number) => (
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
              <h3 style={{ fontSize: '1.1rem', marginBottom: '0.5rem' }}>{selectedService.title}</h3>
              <p style={{ color: 'hsl(var(--text-secondary))', fontSize: '0.82rem', lineHeight: 1.5, background: 'hsl(var(--bg-surface))', padding: '0.75rem', borderRadius: 'var(--radius-sm)' }}>
                {selectedService.description || 'No description.'}
              </p>
            </div>

            {/* Packages */}
            <div className="card" style={{ background: 'hsl(var(--bg-surface))' }}>
              <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600, marginBottom: '0.5rem' }}>
                Packages
              </h4>
              {sortedPackages(selectedService.packages).map((pkg: ServicePackage) => (
                <div key={pkg.tier} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0.5rem 0', borderBottom: '1px solid hsl(var(--border))', fontSize: '0.82rem' }}>
                  <div>
                    <span className="badge badge-info" style={{ marginRight: '0.5rem', textTransform: 'capitalize' }}>{pkg.tier}</span>
                    <span style={{ fontWeight: 500 }}>{pkg.name || '—'}</span>
                    {pkg.is_popular && <span className="badge badge-warning" style={{ marginLeft: '0.5rem' }}>Popular</span>}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: 'hsl(var(--text-tertiary))' }}>
                      <Clock size={12} /> {pkg.delivery_days}d
                    </span>
                    <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: 'hsl(var(--text-tertiary))' }}>
                      <Layers size={12} /> {pkg.revisions} rev
                    </span>
                    <span style={{ fontWeight: 700 }}>{formatGhs(pkg.price)}</span>
                  </div>
                </div>
              ))}
              {(!selectedService.packages || selectedService.packages.length === 0) && (
                <div style={{ fontSize: '0.82rem', color: 'hsl(var(--text-tertiary))' }}>No packages</div>
              )}
            </div>

            {/* Meta */}
            <div className="card" style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem', background: 'hsl(var(--bg-surface))' }}>
              {[
                [<><User size={13} /> Provider</>, `${selectedService.provider?.full_name || 'Unknown'} (${selectedService.provider?.email || 'no email'})`],
                [<><Building size={13} /> Institutions</>, selectedService.institution_codes?.length ? selectedService.institution_codes.join(', ') : 'All institutions'],
                ['Search tags', selectedService.search_tags?.length ? selectedService.search_tags.join(', ') : '—'],
                [<><Star size={13} /> Rating</>, `${Number(selectedService.average_rating || 0).toFixed(2)} (${selectedService.review_count || 0} reviews)`],
                ['Listed', new Date(selectedService.created_at).toLocaleString()],
              ].map(([label, value], i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.82rem' }}>
                  <span style={{ color: 'hsl(var(--text-tertiary))', display: 'flex', alignItems: 'center', gap: '4px' }}>{label}</span>
                  <span style={{ fontWeight: 500 }}>{value}</span>
                </div>
              ))}
            </div>

            {/* Edit Form */}
            <form onSubmit={handleUpdateStatus} style={{ display: 'flex', flexDirection: 'column', gap: '0.875rem' }}>
              <h4 style={{ fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.05em', fontWeight: 600 }}>Moderate Listing</h4>
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label className="form-label">Status</label>
                <select className="form-control" value={editStatus} onChange={(e) => setEditStatus(e.target.value)}>
                  <option value="active">Active (visible in Discover)</option>
                  <option value="paused">Paused (hidden from Discover)</option>
                  <option value="inactive">Inactive</option>
                </select>
              </div>
              <div style={{ display: 'flex', gap: '0.625rem', marginTop: '0.5rem' }}>
                <button type="button" className="btn btn-danger"
                  onClick={() => handleDeleteService(selectedService.id, selectedService.title)}>
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
