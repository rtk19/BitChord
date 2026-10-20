// Loaded only in the bundled main frame, before application scripts.
(() => {
  'use strict';
  Object.defineProperty(window, '__BITCHORD_IOS__', { value: true });
  window.__bcNativeCall = (method, params = {}) => window.webkit.messageHandlers.bitchord.postMessage({ protocol: 1, method, params });
  const browserFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const request = new Request(input, init);
    if (!/^https?:/.test(request.url)) return browserFetch(input, init);
    if (request.signal.aborted) throw request.signal.reason;
    const bytes = request.method === 'GET' || request.method === 'HEAD' ? null : new Uint8Array(await request.arrayBuffer());
    let body;
    if (bytes) {
      let binary = '';
      for (let offset = 0; offset < bytes.length; offset += 0x8000) binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
      body = btoa(binary);
    }
    const exchange = window.__bcNativeCall('http.fetch', {
      url: request.url, method: request.method, headers: Object.fromEntries(request.headers),
      ...(body !== undefined ? { body, bodyEncoding: 'base64' } : {}),
    });
    const response = await new Promise((resolve, reject) => {
      const aborted = () => reject(request.signal.reason);
      if (request.signal.aborted) { reject(request.signal.reason); return; }
      request.signal.addEventListener('abort', aborted, { once: true });
      exchange.then(resolve, reject).finally(() => request.signal.removeEventListener('abort', aborted));
    });
    if (request.signal.aborted) throw request.signal.reason;
    const payload = response.bodyEncoding === 'base64' ? Uint8Array.from(atob(response.body), c => c.charCodeAt(0)) : response.body;
    const result = new Response([204, 205, 304].includes(response.status) ? null : payload, { status: response.status, headers: response.headers });
    Object.defineProperty(result, 'url', { value: response.url });
    return result;
  };
})();
