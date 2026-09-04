/**
 * PWA service-worker registration for the admin portal.
 *
 * Registered in production builds only. When a new service worker takes over
 * (i.e. a fresh deploy), the page reloads once so the running app always
 * matches the cached shell. First installs do not trigger a reload.
 */
export function registerServiceWorker(): void {
  if (!('serviceWorker' in navigator)) return;
  if (!import.meta.env.PROD) return;

  const hadController = navigator.serviceWorker.controller != null;
  let reloaded = false;

  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!hadController || reloaded) return;
    reloaded = true;
    window.location.reload();
  });

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((error) => {
      console.warn('[pwa] service worker registration failed:', error);
    });
  });
}

/** True when the app is running as an installed PWA (standalone window). */
export function isStandalone(): boolean {
  if (window.matchMedia('(display-mode: standalone)').matches) return true;
  const nav = window.navigator as Navigator & { standalone?: boolean };
  return nav.standalone === true;
}
