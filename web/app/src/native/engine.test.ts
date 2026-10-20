// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';
const mocks = vi.hoisted(() => ({ resolve: vi.fn(), session: { player: {} } }));
vi.mock('@/playback/youtube/innertube', () => ({ getInnertube: async () => ({ session: mocks.session }) }));
vi.mock('@/playback/youtube/resolver', () => ({ CLIENT_ATTEMPTS: 3, resolvePlayer: mocks.resolve, usesWebPo: () => false }));
vi.mock('@/playback/youtube/botguard', () => ({ botguard: { mint: vi.fn() } }));
import { loadIOSAudio } from './engine';
import { createIOSAudio } from './ios';

const resolved = (formats: unknown[], client = 'VISIONOS') => ({ client, info: {
  streaming_data: { adaptive_formats: formats }, basic_info: { title: 'Track', author: 'Artist', duration: 180, thumbnail: [] },
} });
const aac = { itag: 140, bitrate: 128000, has_audio: true, has_video: false, mime_type: 'audio/mp4', url: 'https://test.googlevideo.com/audio', decipher: async () => 'https://test.googlevideo.com/audio' };

afterEach(() => { mocks.resolve.mockReset(); delete window.__bcNativeCall; });

describe('iOS stream loading', () => {
  it('skips an unsupported codec and tries another client for native AAC playback', async () => {
    mocks.resolve.mockResolvedValueOnce(resolved([{ ...aac, mime_type: 'audio/webm' }]))
      .mockResolvedValueOnce(resolved([aac], 'YTMUSIC'));
    window.__bcNativeCall = vi.fn().mockResolvedValue({});
    const track = await loadIOSAudio(createIOSAudio(), 'video', 20, false, () => {});
    expect(track.format).toContain('AAC');
    expect(mocks.resolve).toHaveBeenCalledTimes(2);
    expect(window.__bcNativeCall).toHaveBeenCalledWith('audio.load', expect.objectContaining({ startSec: 20, autoplay: false, url: aac.url }));
  });

  it('does not start a stale track after another selection supersedes resolution', async () => {
    mocks.resolve.mockResolvedValue(resolved([aac]));
    window.__bcNativeCall = vi.fn();
    let checks = 0;
    const current = () => { if (++checks > 1) throw new Error('Superseded'); };
    await expect(loadIOSAudio(createIOSAudio(), 'old-video', 0, true, current)).rejects.toThrow('Superseded');
    expect(window.__bcNativeCall).not.toHaveBeenCalled();
  });

  it('tries the next client if AVPlayer refuses the first stream', async () => {
    mocks.resolve.mockResolvedValueOnce(resolved([aac])).mockResolvedValueOnce(resolved([aac], 'YTMUSIC'));
    window.__bcNativeCall = vi.fn().mockRejectedValueOnce(new Error('HTTP 403')).mockResolvedValueOnce({});
    const track = await loadIOSAudio(createIOSAudio(), 'video', 0, true, () => {});
    expect(track.client).toBe('YTMUSIC');
    expect(window.__bcNativeCall).toHaveBeenCalledTimes(2);
  });
});
