import React, { useEffect, useMemo, useRef, useState } from 'react';
import { supabase } from '../supabaseClient';
import { uploadToR2 } from '../r2Client';
import {
  Megaphone,
  Plus,
  Save,
  Loader,
  Eye,
  Edit3,
  Trash2,
  Power,
  Link2,
  ImagePlus,
  Bold,
  Italic,
  Heading2,
  Smile,
  X,
  ArrowLeft,
  Search,
  Monitor,
} from 'lucide-react';
import { useAlert } from '../components/use-alert';
import { useConfirm } from '../components/use-alert';

interface Announcement {
  id: string;
  title: string;
  content: string;
  target_screens: string[];
  max_views: number;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

// ─────────────────────────────────────────────────────────────────────────────
// Every named route in the mobile app (lib/main.dart onGenerateRoute), grouped
// for the screen picker. Keep in sync when routes are added to the app.
// ─────────────────────────────────────────────────────────────────────────────
const SCREEN_GROUPS: { group: string; screens: { path: string; label: string }[] }[] = [
  {
    group: 'Main',
    screens: [
      { path: '/home', label: 'Home' },
      { path: '/explore', label: 'Explore' },
      { path: '/search', label: 'Search' },
      { path: '/clips', label: 'Clips (Video Feed)' },
      { path: '/cart', label: 'Cart' },
      { path: '/checkout', label: 'Checkout' },
      { path: '/wishlist', label: 'Wishlist' },
      { path: '/notifications', label: 'Notifications' },
      { path: '/messages', label: 'Messages' },
      { path: '/services', label: 'Services' },
    ],
  },
  {
    group: 'Wallet & Orders',
    screens: [
      { path: '/wallet', label: 'Wallet' },
      { path: '/orders', label: 'Buyer Orders' },
      { path: '/order-detail', label: 'Order Detail' },
    ],
  },
  {
    group: 'Account',
    screens: [
      { path: '/account', label: 'Account' },
      { path: '/profile', label: 'Profile' },
      { path: '/edit-profile', label: 'Edit Profile' },
      { path: '/following', label: 'Followers & Following' },
    ],
  },
  {
    group: 'Seller',
    screens: [
      { path: '/become-seller', label: 'Become a Seller' },
      { path: '/seller-dashboard', label: 'Seller Dashboard' },
      { path: '/seller-reviews', label: 'Seller Reviews' },
      { path: '/seller-analytics', label: 'Seller Analytics' },
      { path: '/seller-video-analytics', label: 'Video Analytics' },
      { path: '/seller-verify', label: 'Seller Verification' },
      { path: '/seller-profile-verification', label: 'Profile Verification' },
      { path: '/seller-permissions', label: 'Buyer Permissions' },
      { path: '/business-profile', label: 'Business Profile' },
      { path: '/edit-business-profile', label: 'Edit Business Profile' },
      { path: '/create-listing', label: 'Create Listing' },
      { path: '/sell', label: 'Sell' },
    ],
  },
  {
    group: 'Discover',
    screens: [
      { path: '/product', label: 'Product Detail' },
      { path: '/curated-collection', label: 'Curated Collection' },
    ],
  },
  {
    group: 'Info & Legal',
    screens: [
      { path: '/about', label: 'About Instiy' },
      { path: '/about-legal', label: 'About & Legal' },
      { path: '/faq', label: 'FAQ' },
      { path: '/privacy-policy', label: 'Privacy Policy' },
      { path: '/terms-conditions', label: 'Terms & Conditions' },
    ],
  },
  {
    group: 'Auth & System',
    screens: [
      { path: '/get-started', label: 'Get Started' },
      { path: '/login', label: 'Login' },
      { path: '/forgot-password', label: 'Forgot Password' },
      { path: '/reset-password', label: 'Reset Password' },
      { path: '/suspended', label: 'Suspended' },
    ],
  },
];

const ALL_SCREENS = SCREEN_GROUPS.flatMap((g) => g.screens);

const labelFor = (path: string) => ALL_SCREENS.find((s) => s.path === path)?.label ?? path;

// ─────────────────────────────────────────────────────────────────────────────
// Emoji palette — plain unicode, rendered natively by the app's markdown view.
// ─────────────────────────────────────────────────────────────────────────────
const EMOJI_CATEGORIES: { name: string; emojis: string[] }[] = [
  {
    name: 'Smileys',
    emojis: '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😋 😛 😜 🤪 😝 🤗 🤭 🤫 🤔 😐 😑 😶 😏 😒 🙄 😮 😯 😲 😳 🥺 😢 😭 😤 😠 😡 🤯 🥳 😎 🤓 🧐 😴 🤤'.split(' '),
  },
  {
    name: 'Gestures',
    emojis: '👋 🤚 🖐 ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 👇 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 💪'.split(' '),
  },
  {
    name: 'Hearts & Celebration',
    emojis: '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 💔 💕 💖 💘 💝 🎉 🎊 🎂 🎁 🎈 🎆 🎇 ✨ 🌟 ⭐ ⚡ 🔥 💥 🌈 ☀️ 🌙 ❄️ 💯 ✅ ❌ 🚫 ⚠️ 🔔 📣 🏆 🥇 🎯 🆕 🚀 📈'.split(' '),
  },
  {
    name: 'Objects & Food',
    emojis: '📱 💻 ⌚ 📷 🔋 💳 💎 🛍 🛒 📦 🚚 📍 🏠 🏢 🏫 🍜 🍕 🍔 🍟 🌮 🍩 🍪 ☕ 🍵 🥤 🍎 🍇 🍉 🍓 🥑 🌽 💰 🎁 🎮 🎵 🎶'.split(' '),
  },
];

export const Announcements: React.FC = () => {
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  // null = list view, otherwise the id being edited ('new' for a fresh one)
  const [editingId, setEditingId] = useState<string | null>(null);
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [selectedScreens, setSelectedScreens] = useState<string[]>([]);
  const [maxViews, setMaxViews] = useState(1);
  const [isActive, setIsActive] = useState(true);
  const [previewMode, setPreviewMode] = useState(false);
  const [emojiOpen, setEmojiOpen] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [screenSearch, setScreenSearch] = useState('');

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const { showAlert, AlertComponent } = useAlert();
  const { showConfirm, ConfirmComponent } = useConfirm();

  const fetchAnnouncements = async () => {
    try {
      setLoading(true);
      const { data, error } = await supabase
        .from('app_announcements')
        .select('*')
        .order('created_at', { ascending: false });
      if (error) throw error;
      setAnnouncements(data || []);
    } catch (error) {
      console.error('Error fetching announcements:', error);
      showAlert('Error', 'Failed to load announcements. Please refresh the page.', 'error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { fetchAnnouncements(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, []);

  const startNew = () => {
    setEditingId('new');
    setTitle('');
    setContent('');
    setSelectedScreens([]);
    setMaxViews(1);
    setIsActive(true);
    setPreviewMode(false);
    setEmojiOpen(false);
    setScreenSearch('');
  };

  const startEdit = (a: Announcement) => {
    setEditingId(a.id);
    setTitle(a.title);
    setContent(a.content);
    setSelectedScreens(a.target_screens || []);
    setMaxViews(a.max_views);
    setIsActive(a.is_active);
    setPreviewMode(false);
    setEmojiOpen(false);
    setScreenSearch('');
  };

  const handleSave = async () => {
    if (!content.trim()) {
      showAlert('Missing content', 'Write the announcement message before saving.', 'error');
      return;
    }
    if (selectedScreens.length === 0) {
      showAlert('No screens selected', 'Pick at least one screen where the dialog should appear.', 'error');
      return;
    }
    setSaving(true);
    try {
      const payload = {
        title: title.trim(),
        content,
        target_screens: selectedScreens,
        max_views: Math.max(1, Math.round(maxViews) || 1),
        is_active: isActive,
      };
      const { error } = editingId === 'new'
        ? await supabase.from('app_announcements').insert(payload)
        : await supabase.from('app_announcements').update(payload).eq('id', editingId);
      if (error) throw error;
      setEditingId(null);
      await fetchAnnouncements();
      showAlert('Saved', 'Announcement saved.', 'success');
    } catch (error) {
      console.error('Error saving announcement:', error);
      showAlert('Error', 'Failed to save the announcement. Please try again.', 'error');
    } finally {
      setSaving(false);
    }
  };

  const toggleActive = async (a: Announcement) => {
    try {
      const { error } = await supabase
        .from('app_announcements')
        .update({ is_active: !a.is_active })
        .eq('id', a.id);
      if (error) throw error;
      await fetchAnnouncements();
    } catch (error) {
      console.error('Error toggling announcement:', error);
      showAlert('Error', 'Failed to update the announcement.', 'error');
    }
  };

  const remove = (a: Announcement) => {
    showConfirm(
      'Delete announcement?',
      'This permanently removes the dialog from the app.',
      async () => {
        try {
          const { error } = await supabase.from('app_announcements').delete().eq('id', a.id);
          if (error) throw error;
          await fetchAnnouncements();
        } catch (error) {
          console.error('Error deleting announcement:', error);
          showAlert('Error', 'Failed to delete the announcement.', 'error');
        }
      },
      { variant: 'danger', confirmLabel: 'Delete' },
    );
  };

  // ── Editor helpers ────────────────────────────────────────────────────────
  const insertAtCursor = (text: string) => {
    const el = textareaRef.current;
    if (!el) {
      setContent((c) => c + text);
      return;
    }
    const start = el.selectionStart ?? content.length;
    const end = el.selectionEnd ?? content.length;
    const next = content.slice(0, start) + text + content.slice(end);
    setContent(next);
    requestAnimationFrame(() => {
      el.focus();
      const pos = start + text.length;
      el.setSelectionRange(pos, pos);
    });
  };

  const wrapSelection = (marker: string, placeholder = 'text') => {
    const el = textareaRef.current;
    if (!el) return;
    const start = el.selectionStart ?? 0;
    const end = el.selectionEnd ?? 0;
    const selected = content.slice(start, end) || placeholder;
    const next = content.slice(0, start) + marker + selected + marker + content.slice(end);
    setContent(next);
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(start + marker.length, start + marker.length + selected.length);
    });
  };

  const insertLink = () => {
    const url = window.prompt('Link URL (opens in the browser when tapped)', 'https://');
    if (!url) return;
    const el = textareaRef.current;
    const selected = el ? content.slice(el.selectionStart ?? 0, el.selectionEnd ?? 0) : '';
    insertAtCursor(`[${selected || 'link text'}](${url})`);
  };

  const handleImageSelected = async (file: File | undefined) => {
    if (!file) return;
    setUploadingImage(true);
    try {
      const url = await uploadToR2(file, 'announcements');
      insertAtCursor(`\n![](${url})\n`);
    } catch (error) {
      console.error('Error uploading image:', error);
      showAlert('Upload failed', 'The image could not be uploaded. Please try again.', 'error');
    } finally {
      setUploadingImage(false);
      if (imageInputRef.current) imageInputRef.current.value = '';
    }
  };

  // ── Preview renderer (mirrors the app's markdown support) ─────────────────
  const escapeHtml = (text: string): string =>
    text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  const sanitizeHtml = (html: string): string =>
    html
      .replace(/<script[\s\S]*?<\/script>/gi, '')
      .replace(/\bon\w+\s*=\s*["'][^"']*["']/gi, '')
      .replace(/javascript\s*:/gi, '');

  const renderMarkdown = (md: string) => {
    const escaped = escapeHtml(md);
    let html = escaped
      .replace(/^### (.+)$/gm, '<h3>$1</h3>')
      .replace(/^## (.+)$/gm, '<h2>$1</h2>')
      .replace(/^# (.+)$/gm, '<h1>$1</h1>')
      .replace(/!\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g, '<img src="$2" alt="$1" />')
      .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/^> (.+)$/gm, '<blockquote>$1</blockquote>')
      .replace(/^- (.+)$/gm, '<li>$1</li>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br/>');
    html = html.replace(/(<li>.*?<\/li>)+/gs, (match) => `<ul>${match}</ul>`);
    return sanitizeHtml(`<p>${html}</p>`);
  };

  // ── Screen picker helpers ─────────────────────────────────────────────────
  const toggleScreen = (path: string) => {
    setSelectedScreens((prev) =>
      prev.includes(path) ? prev.filter((p) => p !== path) : [...prev, path],
    );
  };

  const toggleGroup = (paths: string[]) => {
    const allSelected = paths.every((p) => selectedScreens.includes(p));
    setSelectedScreens((prev) =>
      allSelected
        ? prev.filter((p) => !paths.includes(p))
        : Array.from(new Set([...prev, ...paths])),
    );
  };

  const filteredGroups = useMemo(() => {
    const q = screenSearch.trim().toLowerCase();
    if (!q) return SCREEN_GROUPS;
    return SCREEN_GROUPS.map((g) => ({
      ...g,
      screens: g.screens.filter(
        (s) => s.label.toLowerCase().includes(q) || s.path.toLowerCase().includes(q),
      ),
    })).filter((g) => g.screens.length > 0);
  }, [screenSearch]);

  // ─────────────────────────────────────────────────────────────────────────
  // List view
  // ─────────────────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '50vh' }}>
        <Loader size={24} className="spin" style={{ color: 'hsl(var(--accent))' }} />
      </div>
    );
  }

  if (editingId !== null) {
    // ───────────────────────────────────────────────────────────────────────
    // Editor view
    // ───────────────────────────────────────────────────────────────────────
    return (
      <div>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
          <div>
            <h1 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', color: 'hsl(var(--text-main))' }}>
              {editingId === 'new' ? 'New Announcement' : 'Edit Announcement'}
            </h1>
            <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginTop: '0.25rem' }}>
              Popup dialog shown in the mobile app on the screens you pick
            </p>
          </div>
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            <button className="btn btn-secondary" onClick={() => setEditingId(null)} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <ArrowLeft size={16} /> Back
            </button>
            <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              {saving ? <Loader size={16} className="spin" /> : <Save size={16} />}
              {saving ? 'Saving...' : 'Save'}
            </button>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 2fr) minmax(0, 1fr)', gap: '1rem', alignItems: 'start' }}>
          {/* ── Content editor ── */}
          <div className="card" style={{ padding: 0, overflow: 'visible' }}>
            <div style={{ padding: '1rem 1rem 0' }}>
              <input
                className="form-control"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Dialog title (e.g. New feature available 🎉)"
                style={{ marginBottom: '0.75rem', fontWeight: 600 }}
              />
            </div>

            <div style={{ position: 'relative' }}>
              {/* Toolbar */}
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '0.25rem',
                  padding: '0.5rem 1rem',
                  borderBottom: '1px solid hsl(var(--border))',
                  flexWrap: 'wrap',
                }}
              >
                <ToolbarButton title="Bold" onClick={() => wrapSelection('**', 'bold text')}><Bold size={15} /></ToolbarButton>
                <ToolbarButton title="Italic" onClick={() => wrapSelection('*', 'italic text')}><Italic size={15} /></ToolbarButton>
                <ToolbarButton title="Heading" onClick={() => insertAtCursor('\n## Heading\n')}><Heading2 size={15} /></ToolbarButton>
                <ToolbarButton title="Link" onClick={insertLink}><Link2 size={15} /></ToolbarButton>
                <ToolbarButton
                  title="Insert image"
                  onClick={() => imageInputRef.current?.click()}
                  disabled={uploadingImage}
                >
                  {uploadingImage ? <Loader size={15} className="spin" /> : <ImagePlus size={15} />}
                </ToolbarButton>
                <ToolbarButton title="Emoji" onClick={() => setEmojiOpen((o) => !o)} active={emojiOpen}><Smile size={15} /></ToolbarButton>
                <div style={{ flex: 1 }} />
                <button
                  onClick={() => setPreviewMode(!previewMode)}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '0.4rem',
                    padding: '0.35rem 0.75rem',
                    borderRadius: '8px',
                    border: '1px solid hsl(var(--border))',
                    background: previewMode ? 'hsl(var(--accent-dim))' : 'transparent',
                    color: previewMode ? 'hsl(var(--accent))' : 'hsl(var(--text-tertiary))',
                    cursor: 'pointer',
                    fontSize: '0.78rem',
                    fontWeight: 500,
                  }}
                >
                  {previewMode ? <Edit3 size={13} /> : <Eye size={13} />}
                  {previewMode ? 'Edit' : 'Preview'}
                </button>
              </div>

              {/* Emoji palette */}
              {emojiOpen && (
                <div
                  style={{
                    position: 'absolute',
                    top: '100%',
                    left: '1rem',
                    right: '1rem',
                    zIndex: 30,
                    marginTop: '0.25rem',
                    background: 'hsl(var(--bg-card))',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '10px',
                    boxShadow: '0 8px 24px rgba(0,0,0,0.12)',
                    padding: '0.75rem',
                    maxHeight: '240px',
                    overflowY: 'auto',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.5rem' }}>
                    <span style={{ fontSize: '0.75rem', fontWeight: 600, color: 'hsl(var(--text-secondary))' }}>Insert emoji</span>
                    <button onClick={() => setEmojiOpen(false)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'hsl(var(--text-tertiary))', display: 'flex' }}>
                      <X size={14} />
                    </button>
                  </div>
                  {EMOJI_CATEGORIES.map((cat) => (
                    <div key={cat.name} style={{ marginBottom: '0.6rem' }}>
                      <div style={{ fontSize: '0.7rem', color: 'hsl(var(--text-tertiary))', marginBottom: '0.3rem', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                        {cat.name}
                      </div>
                      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(34px, 1fr))', gap: '2px' }}>
                        {cat.emojis.map((emoji, i) => (
                          <button
                            key={`${cat.name}-${i}`}
                            onClick={() => insertAtCursor(emoji)}
                            style={{
                              fontSize: '1.15rem',
                              padding: '0.25rem',
                              background: 'none',
                              border: 'none',
                              borderRadius: '6px',
                              cursor: 'pointer',
                              lineHeight: 1.3,
                            }}
                            onMouseEnter={(e) => (e.currentTarget.style.background = 'hsl(var(--accent-dim))')}
                            onMouseLeave={(e) => (e.currentTarget.style.background = 'none')}
                          >
                            {emoji}
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            {previewMode ? (
              <div style={{ padding: '1.5rem' }}>
                <div
                  className="markdown-preview"
                  dangerouslySetInnerHTML={{ __html: renderMarkdown(content || '*Nothing to preview yet*') }}
                  style={{ color: 'hsl(var(--text-main))', lineHeight: 1.7, fontSize: '0.9rem' }}
                />
              </div>
            ) : (
              <textarea
                ref={textareaRef}
                value={content}
                onChange={(e) => setContent(e.target.value)}
                placeholder={'Write the announcement in Markdown…\n\n**bold**, *italic*, ## heading, [link](https://…), ![image](https://…), emojis 😊 and - lists are all supported.'}
                style={{
                  width: '100%',
                  minHeight: '340px',
                  padding: '1rem',
                  border: 'none',
                  outline: 'none',
                  resize: 'vertical',
                  fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
                  fontSize: '0.85rem',
                  lineHeight: 1.7,
                  color: 'hsl(var(--text-main))',
                  background: 'transparent',
                  boxSizing: 'border-box',
                  tabSize: 2,
                }}
              />
            )}
          </div>

          {/* ── Settings column ── */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
            <div className="card" style={{ padding: '1rem', display: 'flex', flexDirection: 'column', gap: '0.9rem' }}>
              <label style={{ fontSize: '0.8rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>
                Max times a user sees this dialog
                <input
                  className="form-control"
                  type="number"
                  min={1}
                  value={maxViews}
                  onChange={(e) => setMaxViews(Number(e.target.value))}
                  style={{ marginTop: '0.35rem' }}
                />
              </label>
              <p style={{ fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))', margin: 0, lineHeight: 1.5 }}>
                Counted per user device. The dialog appears at most once per app session, until the count is reached.
              </p>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <input
                  type="checkbox"
                  id="announcement-active"
                  checked={isActive}
                  onChange={(e) => setIsActive(e.target.checked)}
                  style={{ width: '16px', height: '16px', accentColor: 'hsl(var(--accent))' }}
                />
                <label htmlFor="announcement-active" style={{ fontSize: '0.85rem', color: 'hsl(var(--text-main))', cursor: 'pointer' }}>
                  Active (visible in the app)
                </label>
              </div>
            </div>

            {/* Screen picker */}
            <div className="card" style={{ padding: '1rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', marginBottom: '0.5rem' }}>
                <Monitor size={15} style={{ color: 'hsl(var(--accent))' }} />
                <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'hsl(var(--text-main))' }}>
                  Show on screens
                </span>
                <span style={{ marginLeft: 'auto', fontSize: '0.75rem', color: 'hsl(var(--text-tertiary))' }}>
                  {selectedScreens.length} selected
                </span>
              </div>
              <div style={{ position: 'relative', marginBottom: '0.6rem' }}>
                <Search
                  size={13}
                  style={{ position: 'absolute', left: '0.6rem', top: '50%', transform: 'translateY(-50%)', color: 'hsl(var(--text-tertiary))' }}
                />
                <input
                  className="form-control"
                  value={screenSearch}
                  onChange={(e) => setScreenSearch(e.target.value)}
                  placeholder="Search screens…"
                  style={{ paddingLeft: '1.75rem', fontSize: '0.8rem', padding: '0.4rem 0.6rem 0.4rem 1.75rem' }}
                />
              </div>
              <div style={{ maxHeight: '320px', overflowY: 'auto', paddingRight: '0.25rem' }}>
                {filteredGroups.map((group) => (
                  <div key={group.group} style={{ marginBottom: '0.75rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                      <span style={{ fontSize: '0.7rem', fontWeight: 600, color: 'hsl(var(--text-tertiary))', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
                        {group.group}
                      </span>
                      <button
                        onClick={() => toggleGroup(group.screens.map((s) => s.path))}
                        style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: '0.68rem', color: 'hsl(var(--accent))', padding: 0, fontWeight: 600 }}
                      >
                        {group.screens.every((s) => selectedScreens.includes(s.path)) ? 'Unselect all' : 'Select all'}
                      </button>
                    </div>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))', gap: '0.15rem' }}>
                      {group.screens.map((screen) => (
                        <label
                          key={screen.path}
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            gap: '0.4rem',
                            fontSize: '0.78rem',
                            color: 'hsl(var(--text-main))',
                            cursor: 'pointer',
                            padding: '0.25rem 0.35rem',
                            borderRadius: '6px',
                          }}
                        >
                          <input
                            type="checkbox"
                            checked={selectedScreens.includes(screen.path)}
                            onChange={() => toggleScreen(screen.path)}
                            style={{ width: '14px', height: '14px', accentColor: 'hsl(var(--accent))', flexShrink: 0 }}
                          />
                          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }} title={screen.path}>
                            {screen.label}
                          </span>
                        </label>
                      ))}
                    </div>
                  </div>
                ))}
                {filteredGroups.length === 0 && (
                  <p style={{ fontSize: '0.8rem', color: 'hsl(var(--text-tertiary))', textAlign: 'center', padding: '1rem 0' }}>
                    No screens match “{screenSearch}”.
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>

        <input
          ref={imageInputRef}
          type="file"
          accept="image/*"
          style={{ display: 'none' }}
          onChange={(e) => handleImageSelected(e.target.files?.[0])}
        />
        {AlertComponent}
        {ConfirmComponent}
      </div>
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // List view
  // ─────────────────────────────────────────────────────────────────────────
  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem' }}>
        <div>
          <h1 style={{ fontSize: '1.5rem', fontWeight: 700, fontFamily: 'var(--font-title)', color: 'hsl(var(--text-main))' }}>
            App Announcements
          </h1>
          <p style={{ color: 'hsl(var(--text-tertiary))', fontSize: '0.85rem', marginTop: '0.25rem' }}>
            Popup dialogs shown in the mobile app on selected screens
          </p>
        </div>
        <button className="btn btn-primary" onClick={startNew} style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <Plus size={16} /> New Announcement
        </button>
      </div>

      {announcements.length === 0 ? (
        <div className="card" style={{ padding: '3rem', textAlign: 'center' }}>
          <Megaphone size={32} style={{ color: 'hsl(var(--text-tertiary))', marginBottom: '0.75rem' }} />
          <p style={{ color: 'hsl(var(--text-tertiary))', margin: 0 }}>
            No announcements yet. Create one to pop up a message inside the app.
          </p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
          {announcements.map((a) => (
            <div key={a.id} className="card" style={{ padding: '1rem 1.25rem', display: 'flex', alignItems: 'center', gap: '1rem' }}>
              <div
                style={{
                  width: '38px',
                  height: '38px',
                  borderRadius: '10px',
                  background: 'hsl(var(--accent-dim))',
                  color: 'hsl(var(--accent))',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0,
                }}
              >
                <Megaphone size={18} />
              </div>
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' }}>
                  <span style={{ fontWeight: 600, fontSize: '0.9rem', color: 'hsl(var(--text-main))' }}>
                    {a.title || <em style={{ color: 'hsl(var(--text-tertiary))' }}>Untitled</em>}
                  </span>
                  <span className={`badge ${a.is_active ? 'badge-success' : 'badge-danger'}`}>
                    {a.is_active ? 'Active' : 'Paused'}
                  </span>
                </div>
                <p
                  style={{
                    margin: '0.25rem 0 0',
                    fontSize: '0.78rem',
                    color: 'hsl(var(--text-tertiary))',
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {a.content.replace(/[#*>\-![\]()]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 110) || '—'}
                </p>
                <div style={{ display: 'flex', gap: '0.75rem', marginTop: '0.35rem', fontSize: '0.72rem', color: 'hsl(var(--text-tertiary))', flexWrap: 'wrap' }}>
                  <span>
                    {a.target_screens.length} screen{a.target_screens.length === 1 ? '' : 's'}
                    {a.target_screens.length > 0 && ` (${a.target_screens.slice(0, 3).map(labelFor).join(', ')}${a.target_screens.length > 3 ? '…' : ''})`}
                  </span>
                  <span>· max {a.max_views} view{a.max_views === 1 ? '' : 's'} per user</span>
                  <span>· updated {new Date(a.updated_at).toLocaleDateString()}</span>
                </div>
              </div>
              <div style={{ display: 'flex', gap: '0.4rem', flexShrink: 0 }}>
                <button className="btn btn-secondary btn-sm" title={a.is_active ? 'Pause' : 'Activate'} onClick={() => toggleActive(a)}>
                  <Power size={14} />
                </button>
                <button className="btn btn-secondary btn-sm" title="Edit" onClick={() => startEdit(a)}>
                  <Edit3 size={14} />
                </button>
                <button className="btn btn-danger btn-sm" title="Delete" onClick={() => remove(a)}>
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <style>{`
        .markdown-preview h1 { font-size: 1.5rem; font-weight: 700; margin: 1.5rem 0 0.75rem; color: hsl(var(--text-main)); }
        .markdown-preview h2 { font-size: 1.2rem; font-weight: 600; margin: 1.25rem 0 0.5rem; color: hsl(var(--text-main)); }
        .markdown-preview h3 { font-size: 1rem; font-weight: 600; margin: 1rem 0 0.5rem; color: hsl(var(--text-main)); }
        .markdown-preview p { margin: 0.5rem 0; }
        .markdown-preview ul { margin: 0.5rem 0; padding-left: 1.5rem; }
        .markdown-preview li { margin: 0.25rem 0; }
        .markdown-preview em { color: hsl(var(--text-tertiary)); }
        .markdown-preview a { color: hsl(var(--accent)); text-decoration: underline; }
        .markdown-preview img { max-width: 100%; border-radius: 10px; margin: 0.5rem 0; }
        .markdown-preview blockquote { border-left: 3px solid hsl(var(--accent)); margin: 0.5rem 0; padding: 0.35rem 0.75rem; background: hsl(var(--accent-dim)); border-radius: 0 8px 8px 0; }
      `}</style>
      {AlertComponent}
      {ConfirmComponent}
    </div>
  );
};

const ToolbarButton: React.FC<{
  title: string;
  onClick: () => void;
  active?: boolean;
  disabled?: boolean;
  children: React.ReactNode;
}> = ({ title, onClick, active, disabled, children }) => (
  <button
    title={title}
    onClick={onClick}
    disabled={disabled}
    style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: '30px',
      height: '30px',
      borderRadius: '7px',
      border: 'none',
      cursor: disabled ? 'default' : 'pointer',
      background: active ? 'hsl(var(--accent-dim))' : 'transparent',
      color: active ? 'hsl(var(--accent))' : 'hsl(var(--text-tertiary))',
      opacity: disabled ? 0.5 : 1,
    }}
    onMouseEnter={(e) => { if (!disabled) e.currentTarget.style.background = 'hsl(var(--bg-hover, rgba(0,0,0,0.05)))'; }}
    onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = 'transparent'; }}
  >
    {children}
  </button>
);
