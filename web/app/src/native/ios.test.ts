// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createIOSAudio, nativeDeckId } from './ios';

afterEach(() => { delete window.__bcNativeCall; vi.restoreAllMocks(); });

describe('native audio integration', () => {
  it('keeps independent decks and sends seek, volume and playback commands to the correct player', async () => {
    const call = vi.fn().mockResolvedValue({});
    window.__bcNativeCall = call;
    const front = createIOSAudio();
    const back = createIOSAudio();
    front.currentTime = 35;
    back.volume = 0.25;
    await front.play();
    expect(call).toHaveBeenCalledWith('audio.seek', { id: nativeDeckId(front), seconds: 35 });
    expect(call).toHaveBeenCalledWith('audio.volume', { id: nativeDeckId(back), volume: 0.25 });
    expect(call).toHaveBeenCalledWith('audio.play', { id: nativeDeckId(front) });
  });

  it('drives the upstream event listeners from native state, without changing the other deck', () => {
    const front = createIOSAudio();
    const back = createIOSAudio();
    const playing = vi.fn();
    front.addEventListener('playing', playing);
    window.dispatchEvent(new CustomEvent('bitchord:audio', { detail: {
      id: nativeDeckId(front), event: 'playing', position: 8, duration: 180, paused: false, ended: false, rate: 1,
    } }));
    expect(playing).toHaveBeenCalledOnce();
    expect(front.currentTime).toBe(8);
    expect(front.duration).toBe(180);
    expect(front.paused).toBe(false);
    expect(back.paused).toBe(true);
    expect(back.currentTime).toBe(0);
  });

  it('propagates native play failures so the queue can show an actionable error', async () => {
    window.__bcNativeCall = vi.fn().mockRejectedValue(new Error('Audio session interrupted'));
    await expect(createIOSAudio().play()).rejects.toThrow('Audio session interrupted');
  });
});
