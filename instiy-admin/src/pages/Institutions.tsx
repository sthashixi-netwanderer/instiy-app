import React, { useEffect, useState, useRef } from 'react';
import { supabase } from '../supabaseClient';
import { uploadToR2 } from '../r2Client';
import { Plus, Edit2, Trash2, Loader, X, Upload, Search, Landmark, Link as LinkIcon, MapPin } from 'lucide-react';

interface Institution {
  id: string;
  code: string;
  name: string;
  logo_url?: string;
  location?: string;
  url?: string;
  region?: string;
  created_at: string;
}

export const Institutions: React.FC = () => {
  const [institutions, setInstitutions] = useState<Institution[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [editingInstitution, setEditingInstitution] = useState<Institution | null>(null);
  const [code, setCode] = useState('');
  const [name, setName] = useState('');
  const [logoUrl, setLogoUrl] = useState('');
  const [location, setLocation] = useState('');
  const [url, setUrl] = useState('');
  const [region, setRegion] = useState('');
  const [uploadingLogo, setUploadingLogo] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const fetchInstitutions = async () => {
    try {
      setLoading(true);
      let query = supabase.from('institutions').select('*').order('name', { ascending: true });
      if (searchQuery.trim()) query = query.or(`name.ilike.%${searchQuery}%,code.ilike.%${searchQuery}%,location.ilike.%${searchQuery}%`);
      const { data, error } = await query;
      if (error) throw error;
      setInstitutions(data || []);
    } catch (error) { console.error('Error:', error); }
    finally { setLoading(false); }
  };

  useEffect(() => { fetchInstitutions(); }, [searchQuery]);

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
        const parts: string[] = [];
        let inQuotes = false;
        let current = '';
        for (let j = 0; j < line.length; j++) {
          const char = line[j];
          if (char === '"') inQuotes = !inQuotes;
          else if (char === ',' && !inQuotes) { parts.push(current.trim()); current = ''; }
          else current += char;
        }
        parts.push(current.trim());

        if (parts.length >= 3) {
          toInsert.push({
            id: parts[0], code: parts[1], name: parts[2].replace(/^"|"$/g, ''),
            logo_url: parts[3] || null, location: parts[4] || null,
            url: parts[5] || null, region: parts[6] || null,
            created_at: new Date().toISOString()
          });
        }
      }

      if (toInsert.length === 0) { alert('No valid institutions found.'); return; }
      setLoading(true);
      try {
        const { error } = await supabase.from('institutions').upsert(toInsert, { onConflict: 'code' });
        if (error) throw error;
        alert(`Imported ${toInsert.length} institutions!`);
        fetchInstitutions();
      } catch (err: any) { alert('Error: ' + err.message); }
      finally { setLoading(false); }
    };
    reader.readAsText(file);
    e.target.value = '';
  };

  const handleLogoFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingLogo(true);
    try { setLogoUrl(await uploadToR2(file, 'institutions/logos')); }
    catch (err: any) { alert('Error uploading: ' + err.message); }
    finally { setUploadingLogo(false); }
  };

  const openAddModal = () => { setEditingInstitution(null); setCode(''); setName(''); setLogoUrl(''); setLocation(''); setUrl(''); setRegion(''); setShowModal(true); };
  const openEditModal = (inst: Institution) => { setEditingInstitution(inst); setCode(inst.code); setName(inst.name); setLogoUrl(inst.logo_url || ''); setLocation(inst.location || ''); setUrl(inst.url || ''); setRegion(inst.region || ''); setShowModal(true); };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!code.trim() || !name.trim()) return;
    setSubmitting(true);
    const payload = { code: code.trim().toUpperCase(), name: name.trim(), logo_url: logoUrl || null, location: location.trim() || null, url: url.trim() || null, region: region.trim() || null };
    try {
      if (editingInstitution) {
        const { error } = await supabase.from('institutions').update(payload).eq('id', editingInstitution.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from('institutions').insert(payload);
        if (error) throw error;
      }
      setShowModal(false);
      fetchInstitutions();
    } catch (error) { alert('Error: ' + (error as any).message); }
    finally { setSubmitting(false); }
  };

  const handleDelete = async (id: string, instName: string) => {
    if (!window.confirm(`Delete "${instName}"?`)) return;
    try {
      const { error } = await supabase.from('institutions').delete().eq('id', id);
      if (error) throw error;
      setInstitutions(institutions.filter(i => i.id !== id));
    } catch (error) { alert('Error: ' + (error as any).message); }
  };

  return (
    <div className="animated-fade-in">
      <div className="page-header">
        <div>
          <h1 className="page-title">Institutions</h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', marginTop: '0.2rem', fontSize: '0.85rem' }}>Manage universities and campus details</p>
        </div>
        <div style={{ display: 'flex', gap: '0.625rem' }}>
          <input type="file" accept=".csv" style={{ display: 'none' }} id="inst-csv-file-input" onChange={handleImportCSV} />
          <label htmlFor="inst-csv-file-input" className="btn btn-secondary" style={{ cursor: 'pointer' }}>Import CSV</label>
          <button className="btn btn-primary" onClick={openAddModal}><Plus size={16} /> Add Institution</button>
        </div>
      </div>

      <div className="card" style={{ marginBottom: '1.5rem', padding: '0.875rem' }}>
        <div style={{ position: 'relative', width: '100%', maxWidth: '360px' }}>
          <Search size={16} style={{ position: 'absolute', left: '10px', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }} />
          <input type="text" className="form-control" style={{ paddingLeft: '2.25rem' }}
            placeholder="Search by name, code, or location..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} />
        </div>
      </div>

      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '40vh' }}>
          <Loader className="spin" size={28} style={{ color: 'hsl(var(--accent))' }} />
        </div>
      ) : (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '1rem' }}>
          {institutions.length === 0 ? (
            <div className="card" style={{ gridColumn: '1 / -1', textAlign: 'center', padding: '2.5rem', color: 'hsl(var(--text-tertiary))' }}>
              <Landmark size={40} style={{ margin: '0 auto 0.75rem', display: 'block', opacity: 0.4 }} />
              No institutions yet.
            </div>
          ) : (
            institutions.map((inst) => (
              <div className="card" key={inst.id} style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                  {inst.logo_url ? (
                    <img src={inst.logo_url} alt={`${inst.code} logo`}
                      style={{ width: '44px', height: '44px', borderRadius: 'var(--radius-sm)', objectFit: 'cover', border: '1px solid hsl(var(--border))' }} />
                  ) : (
                    <div style={{ width: '44px', height: '44px', borderRadius: 'var(--radius-sm)', background: 'hsl(var(--bg-surface))', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'hsl(var(--accent))', fontWeight: 700, fontSize: '0.78rem', border: '1px solid hsl(var(--border))' }}>
                      {inst.code.substring(0, 3)}
                    </div>
                  )}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.375rem', marginBottom: '0.15rem' }}>
                      <span className="badge badge-info" style={{ fontSize: '0.65rem', padding: '1px 5px' }}>{inst.code}</span>
                      {inst.region && <span className="badge badge-success" style={{ fontSize: '0.58rem', padding: '1px 4px' }}>{inst.region}</span>}
                    </div>
                    <h3 style={{ fontSize: '0.9rem', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={inst.name}>{inst.name}</h3>
                  </div>
                </div>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem', fontSize: '0.78rem', color: 'hsl(var(--text-tertiary))', padding: '0.375rem 0' }}>
                  {inst.location && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <MapPin size={12} style={{ color: 'hsl(var(--text-tertiary))' }} /> {inst.location}
                    </div>
                  )}
                  {inst.url && (
                    <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <LinkIcon size={12} style={{ color: 'hsl(var(--text-tertiary))' }} />
                      <a href={inst.url} target="_blank" rel="noopener noreferrer" style={{ color: 'hsl(var(--accent))', textDecoration: 'none' }}>
                        {inst.url.replace(/^https?:\/\/(www\.)?/, '')}
                      </a>
                    </div>
                  )}
                </div>

                <div style={{ display: 'flex', gap: '0.375rem', marginTop: 'auto', paddingTop: '0.625rem', borderTop: '1px solid hsl(var(--border))' }}>
                  <button className="btn btn-secondary btn-sm" style={{ flex: 1 }} onClick={() => openEditModal(inst)}><Edit2 size={12} /> Edit</button>
                  <button className="btn btn-danger btn-sm" style={{ flex: '0 0 auto' }} onClick={() => handleDelete(inst.id, inst.name)}><Trash2 size={12} /></button>
                </div>
              </div>
            ))
          )}
        </div>
      )}

      {/* Modal */}
      {showModal && (
        <div className="modal-backdrop">
          <div className="modal-content" style={{ maxWidth: '480px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.25rem', borderBottom: '1px solid hsl(var(--border))', paddingBottom: '0.625rem' }}>
              <h2 style={{ fontSize: '1.1rem', display: 'flex', alignItems: 'center', gap: '0.5rem', fontFamily: 'var(--font-title)' }}>
                <Landmark size={18} style={{ color: 'hsl(var(--accent))' }} />
                {editingInstitution ? 'Edit Institution' : 'Add Institution'}
              </h2>
              <button style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-secondary))', padding: '4px' }} onClick={() => setShowModal(false)}>
                <X size={18} />
              </button>
            </div>

            <form onSubmit={handleSubmit}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 3fr', gap: '0.75rem' }}>
                <div className="form-group">
                  <label className="form-label">Code</label>
                  <input type="text" className="form-control" placeholder="UG" value={code} onChange={(e) => setCode(e.target.value)} required />
                </div>
                <div className="form-group">
                  <label className="form-label">Name</label>
                  <input type="text" className="form-control" placeholder="University of Ghana" value={name} onChange={(e) => setName(e.target.value)} required />
                </div>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem' }}>
                <div className="form-group">
                  <label className="form-label">Location</label>
                  <input type="text" className="form-control" placeholder="Legon" value={location} onChange={(e) => setLocation(e.target.value)} />
                </div>
                <div className="form-group">
                  <label className="form-label">Region</label>
                  <input type="text" className="form-control" placeholder="Greater Accra" value={region} onChange={(e) => setRegion(e.target.value)} />
                </div>
              </div>
              <div className="form-group">
                <label className="form-label">Website</label>
                <input type="url" className="form-control" placeholder="https://ug.edu.gh" value={url} onChange={(e) => setUrl(e.target.value)} />
              </div>

              <div className="form-group">
                <label className="form-label">Logo</label>
                <input type="file" accept="image/*" style={{ display: 'none' }} ref={fileInputRef} onChange={handleLogoFileChange} />
                {logoUrl ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem', background: 'hsl(var(--bg-surface))', padding: '0.625rem', borderRadius: 'var(--radius-sm)', border: '1px solid hsl(var(--border))' }}>
                    <img src={logoUrl} alt="Logo" style={{ width: '48px', height: '48px', borderRadius: '4px', objectFit: 'cover' }} />
                    <div style={{ flex: 1, minWidth: 0, fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{logoUrl}</div>
                    <button type="button" className="btn btn-danger btn-sm" onClick={() => setLogoUrl('')}>Remove</button>
                  </div>
                ) : (
                  <button type="button" className="btn btn-secondary" style={{ width: '100%', borderStyle: 'dashed', borderWidth: '2px', padding: '0.75rem' }} onClick={() => fileInputRef.current?.click()} disabled={uploadingLogo}>
                    {uploadingLogo ? <><Loader size={16} className="spin" /> Uploading...</> : <><Upload size={16} /> Upload Logo</>}
                  </button>
                )}
              </div>

              <div style={{ display: 'flex', gap: '0.625rem', justifyContent: 'flex-end', marginTop: '1.25rem' }}>
                <button type="button" className="btn btn-secondary" onClick={() => setShowModal(false)} disabled={submitting}>Cancel</button>
                <button type="submit" className="btn btn-primary" disabled={submitting || uploadingLogo}>{submitting ? 'Saving...' : 'Save'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
