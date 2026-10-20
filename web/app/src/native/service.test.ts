// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({ home: vi.fn(), playlist: vi.fn(), load: vi.fn(), call: vi.fn().mockResolvedValue({}) }));
vi.mock('@/data/music/api', () => ({ fetchHome: mocks.home, fetchPlaylist: mocks.playlist }));
vi.mock('@/lib/queryClient', () => ({ queryClient: { setQueryData: vi.fn() } }));
vi.mock('@/extension/useExtension', () => ({ extensionQueryKey: ['extension'] }));
vi.mock('./bridge', () => ({ detectIOSHost: () => ({}) }));
vi.mock('./ios', () => ({ createIOSAudio: () => ({}), nativeCall: mocks.call }));
vi.mock('./engine', () => ({ loadIOSAudio: mocks.load }));
import { request } from './service';

beforeEach(() => { mocks.home.mockReset(); mocks.playlist.mockReset(); mocks.load.mockReset(); });

describe('SwiftUI catalogue boundary', () => {
  it('keeps continuations retryable after failure and consumes them after success', async () => {
    const next = vi.fn().mockRejectedValueOnce(new Error('Offline')).mockResolvedValueOnce({ data: ['second'], next: null });
    mocks.home.mockResolvedValue({ data: ['first'], next });
    const first = await request('home', {}) as { cursor: string; data: string[] };
    expect(first.data).toEqual(['first']);
    await expect(request('more', { cursor: first.cursor })).rejects.toThrow('Offline');
    await expect(request('more', { cursor: first.cursor })).resolves.toEqual({ data: ['second'], cursor: null });
    await expect(request('more', { cursor: first.cursor })).rejects.toThrow('expired');
  });

  it('preserves playlist headers and exposes paginated tracks through an opaque cursor', async () => {
    mocks.playlist.mockResolvedValue({ page: { title: 'Album', tracks: ['first'] }, more: async () => ({ data: ['next'], next: null }) });
    const page = await request('playlist', { id: 'VL123' }) as { cursor: string; title: string; tracks: string[] };
    expect(page.title).toBe('Album'); expect(page.tracks).toEqual(['first']);
    await expect(request('more', { cursor: page.cursor })).resolves.toEqual({ data: ['next'], cursor: null });
  });

  it('invalidates an old resolver before it can overwrite a reused native deck', async () => {
    let check: (() => void) | undefined;
    mocks.load.mockImplementation(async (_deck, _id, _start, _autoplay, current) => { check = current; return {}; });
    await request('resolve', { id: 'one', deck: 0 });
    expect(() => check?.()).not.toThrow();
    await request('cancel', { deck: 0 });
    expect(() => check?.()).toThrow('Superseded');
    await expect(request('resolve', { id: 'two', deck: 8 })).rejects.toThrow('Invalid audio deck');
  });
});
