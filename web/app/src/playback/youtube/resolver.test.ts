// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Innertube } from 'youtubei.js/web';
vi.mock('youtubei.js/web', () => ({
  Utils: { generateRandomString: () => 'nonce' },
  YT: { VideoInfo: class { constructor(responses: { data: object }[]) { Object.assign(this, responses[0]!.data); } } },
}));
vi.mock('./botguard', () => ({ botguard: { mint: vi.fn() } }));
import { onSessionChanged, resolvePlayer, unplayableReason } from './resolver';
beforeEach(() => { onSessionChanged(); localStorage.clear(); });
const client = (reason: string) => ({
  session: { context: { client: {} } },
  actions: { execute: vi.fn().mockResolvedValue({ data: { playability_status: { status: 'LOGIN_REQUIRED', reason } } }) },
});
describe('player refusal classification', () => {
  it('tries alternate clients for a bot challenge and does not cache it as an age restriction', async () => {
    const yt = client("Sign in to confirm you're not a bot");
    await expect(resolvePlayer(yt as unknown as Innertube, 'track')).rejects.toMatchObject({ name: 'VerificationRequiredError' });
    expect(yt.actions.execute).toHaveBeenCalledTimes(3);
    expect(unplayableReason('track')).toBeNull();
    // Retry remains possible after a network verification challenge.
    await expect(resolvePlayer(yt as unknown as Innertube, 'track')).rejects.toMatchObject({ name: 'VerificationRequiredError' });
    expect(yt.actions.execute).toHaveBeenCalledTimes(6);
  });
  it('keeps a genuine age gate distinct and remembers that verdict', async () => {
    const yt = client('Sign in to confirm your age');
    await expect(resolvePlayer(yt as unknown as Innertube, 'age-track')).rejects.toMatchObject({ name: 'UnplayableError', ageGated: true });
    expect(unplayableReason('age-track')).toContain('age-restricted');
  });
});
