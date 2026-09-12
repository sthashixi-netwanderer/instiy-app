import { useEffect, useState } from 'react';
import { Download, Share, X } from 'lucide-react';
import { isStandalone } from '../pwa';

/** Prompt event fired by Chromium when the PWA is installable. */
interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

// Permanent hide once the app is installed; dismissals snooze for 7 days.
const INSTALLED_KEY = 'instiy-admin-pwa-installed';
const DISMISSED_AT_KEY = 'instiy-admin-pwa-dismissed-at';
const SNOOZE_MS = 7 * 24 * 60 * 60 * 1000;

function wasRecentlyDismissed(): boolean {
  const raw = localStorage.getItem(DISMISSED_AT_KEY);
  if (raw == null) return false;
  return Date.now() - Number(raw) < SNOOZE_MS;
}

/** Banner promoting PWA installation. Never shown again once installed. */
export const InstallBanner: React.FC = () => {
  const [promptEvent, setPromptEvent] =
    useState<BeforeInstallPromptEvent | null>(null);
  const [visible, setVisible] = useState(false);
  const [isIos, setIsIos] = useState(false);

  useEffect(() => {
    if (localStorage.getItem(INSTALLED_KEY) === '1') return;
    if (isStandalone()) {
      localStorage.setItem(INSTALLED_KEY, '1');
      return;
    }
    if (wasRecentlyDismissed()) return;

    setIsIos(
      /iphone|ipad|ipod/i.test(window.navigator.userAgent) &&
        !(window.navigator as Navigator & { standalone?: boolean })
          .standalone,
    );

    const onBeforeInstall = (e: Event) => {
      e.preventDefault();
      setPromptEvent(e as BeforeInstallPromptEvent);
      setVisible(true);
    };
    const onInstalled = () => {
      localStorage.setItem(INSTALLED_KEY, '1');
      setPromptEvent(null);
      setVisible(false);
    };
    const media = window.matchMedia('(display-mode: standalone)');
    const onDisplayChange = (e: MediaQueryListEvent) => {
      if (e.matches) onInstalled();
    };

    // iOS never fires beforeinstallprompt — show manual steps instead.
    if (
      /iphone|ipad|ipod/i.test(window.navigator.userAgent) &&
      !(window.navigator as Navigator & { standalone?: boolean }).standalone
    ) {
      setVisible(true);
    }

    window.addEventListener('beforeinstallprompt', onBeforeInstall);
    window.addEventListener('appinstalled', onInstalled);
    media.addEventListener('change', onDisplayChange);
    return () => {
      window.removeEventListener('beforeinstallprompt', onBeforeInstall);
      window.removeEventListener('appinstalled', onInstalled);
      media.removeEventListener('change', onDisplayChange);
    };
  }, []);

  if (!visible) return null;

  const dismiss = () => {
    localStorage.setItem(DISMISSED_AT_KEY, String(Date.now()));
    setVisible(false);
  };

  const install = async () => {
    if (promptEvent == null) return;
    await promptEvent.prompt();
    const { outcome } = await promptEvent.userChoice;
    if (outcome === 'accepted') {
      localStorage.setItem(INSTALLED_KEY, '1');
      setVisible(false);
    }
    setPromptEvent(null);
  };

  return (
    <div
      role="complementary"
      aria-label="Install app"
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 60,
        display: 'flex',
        alignItems: 'center',
        gap: '0.75rem',
        padding: '0.6rem 1rem',
        fontSize: '0.8rem',
        color: '#fff',
        background: 'hsl(var(--accent))',
      }}
    >
      {isIos || promptEvent == null ? (
        <Share size={16} style={{ flexShrink: 0 }} />
      ) : (
        <Download size={16} style={{ flexShrink: 0 }} />
      )}
      <span style={{ flex: 1, minWidth: 0 }}>
        {isIos || promptEvent == null ? (
          <>
            Install Instiy Control Room: tap <strong>Share</strong> then{' '}
            <strong>Add to Home Screen</strong>.
          </>
        ) : (
          <>
            <strong>Install Instiy Control Room</strong> for quick access and
            offline support.
          </>
        )}
      </span>
      {promptEvent != null && !isIos && (
        <button
          type="button"
          className="btn btn-sm"
          onClick={install}
          style={{ background: '#fff', color: 'hsl(var(--accent))' }}
        >
          Install
        </button>
      )}
      <button
        type="button"
        aria-label="Dismiss"
        onClick={dismiss}
        style={{
          background: 'none',
          border: 'none',
          color: '#fff',
          cursor: 'pointer',
          padding: '4px',
          display: 'flex',
        }}
      >
        <X size={16} />
      </button>
    </div>
  );
};
