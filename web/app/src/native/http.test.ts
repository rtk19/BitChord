import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';

const script = readFileSync(new URL('../../../../ios/BitChord/Bridge.js', import.meta.url), 'utf8');
function host() {
  const postMessage = vi.fn().mockResolvedValue({ status: 200, headers: { 'content-type': 'application/json' }, body: '{"ok":true}', bodyEncoding: 'text', url: 'https://music.youtube.com/result' });
  const window = { fetch: vi.fn(), webkit: { messageHandlers: { bitchord: { postMessage } } } };
  new Function('window', script)(window);
  return { fetch: window.fetch as unknown as typeof fetch, postMessage, window };
}

describe('bundled iOS HTTP bridge', () => {
  it('preserves binary request bodies and returns the final URL and decoded body', async () => {
    const native = host();
    const response = await native.fetch('https://music.youtube.com/youtubei/v1/player', { method: 'POST', body: new Uint8Array([0, 255, 42]) });
    expect(native.postMessage).toHaveBeenCalledWith(expect.objectContaining({ method: 'http.fetch', params: expect.objectContaining({ method: 'POST', body: 'AP8q', bodyEncoding: 'base64' }) }));
    expect(response.url).toBe('https://music.youtube.com/result');
    expect(await response.json()).toEqual({ ok: true });
  });

  it('returns binary response bytes without UTF-8 corruption', async () => {
    const native = host();
    native.postMessage.mockResolvedValue({ status: 200, headers: {}, body: 'AP8q', bodyEncoding: 'base64', url: 'https://example.com' });
    const response = await native.fetch('https://example.com');
    expect([...new Uint8Array(await response.arrayBuffer())]).toEqual([0, 255, 42]);
  });

  it('aborts an in-flight UI request even while native networking is still pending', async () => {
    const native = host();
    native.postMessage.mockImplementation(() => new Promise(() => {}));
    const abort = new AbortController();
    const response = native.fetch('https://example.com', { signal: abort.signal });
    abort.abort(new Error('Cancelled by navigation'));
    await expect(response).rejects.toThrow('Cancelled by navigation');
  });
});
