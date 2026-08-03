{{flutter_js}}
{{flutter_build_config}}

// Yerel geliştirme sunucusunda eski arayüzün service worker önbelleğinde
// kalmasını önler. Uygulamanın backend ve Ollama kullanımı yine tamamen yereldir.
(async () => {
  if ('serviceWorker' in navigator) {
    const registrations = await navigator.serviceWorker.getRegistrations();
    await Promise.all(registrations.map((registration) => registration.unregister()));
  }
  if ('caches' in window) {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
  }
  await _flutter.loader.load();
})();
