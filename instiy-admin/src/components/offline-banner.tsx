import { useEffect, useState } from 'react';
import { WifiOff } from 'lucide-react';

/** Slim banner shown while the device has no network connection. */
export const OfflineBanner: React.FC = () => {
  const [online, setOnline] = useState(
    typeof navigator === 'undefined' ? true : navigator.onLine,
  );

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener('online', goOnline);
    window.addEventListener('offline', goOffline);
    return () => {
      window.removeEventListener('online', goOnline);
      window.removeEventListener('offline', goOffline);
    };
  }, []);

  if (online) return null;

  return (
    <div
      role="alert"
      style={{
        position: 'sticky',
        top: 0,
        zIndex: 60,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '0.5rem',
        padding: '0.5rem 1rem',
        fontSize: '0.8rem',
        fontWeight: 600,
        color: '#fff',
        background: 'hsl(var(--danger))',
      }}
    >
      <WifiOff size={14} />
      You&apos;re offline — live data is unavailable until you reconnect.
    </div>
  );
};
