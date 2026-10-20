/** Small, versioned boundary to the bundled iOS host. Browser builds use the existing engine. */
export interface NativeAudioState {
  id: number;
  event: string;
  position: number;
  duration: number;
  paused: boolean;
  ended: boolean;
  rate: number;
  error?: string;
}

declare global {
  interface Window {
    __BITCHORD_IOS__?: boolean;
    __bcNativeCall?: (method: string, params: Record<string, unknown>) => Promise<unknown>;
  }
}

export const isIOSApp = () => typeof window !== 'undefined' && window.__BITCHORD_IOS__ === true;

export async function nativeCall<T = unknown>(method: string, params: Record<string, unknown> = {}): Promise<T> {
  if (!window.__bcNativeCall) throw new Error('The iOS host is unavailable');
  return window.__bcNativeCall(method, params) as Promise<T>;
}

let nextDeck = 0;
const deckIds = new WeakMap<HTMLAudioElement, number>();

export function nativeDeckId(audio: HTMLAudioElement): number {
  const id = deckIds.get(audio);
  if (id === undefined) throw new Error('Audio element is not an iOS deck');
  return id;
}

/** Keep the upstream queue, scrubber and lyrics on the same event contract. AVPlayer owns audio. */
export function createIOSAudio(): HTMLAudioElement {
  const audio = new Audio();
  const id = nextDeck++;
  deckIds.set(audio, id);
  let state: NativeAudioState = { id, event: '', position: 0, duration: NaN, paused: true, ended: false, rate: 1 };
  let volume = 1;
  const command = (method: string, params: Record<string, unknown>) => nativeCall(method, { id, ...params });
  const reportError = (error: unknown) => {
    console.error('iOS audio:', error);
    audio.dispatchEvent(new Event('error'));
  };
  Object.defineProperties(audio, {
    currentTime: { get: () => state.position, set: (value: number) => { state.position = value; void command('audio.seek', { seconds: value }).catch(reportError); } },
    duration: { get: () => state.duration },
    paused: { get: () => state.paused },
    ended: { get: () => state.ended },
    readyState: { get: () => Number.isFinite(state.duration) ? 4 : 0 },
    playbackRate: { get: () => state.rate, set: (value: number) => { state.rate = value; void command('audio.rate', { rate: value }).catch(reportError); } },
    volume: { get: () => volume, set: (value: number) => { volume = value; void command('audio.volume', { volume: value }).catch(reportError); } },
    play: { value: async () => { await command('audio.play', {}); } },
    pause: { value: () => { void command('audio.pause', {}).catch(reportError); } },
  });
  window.addEventListener('bitchord:audio', ((event: CustomEvent<NativeAudioState>) => {
    if (event.detail.id !== id) return;
    state = event.detail;
    audio.dispatchEvent(new Event(state.event));
  }) as EventListener);
  return audio;
}
