import type { LoadedTrack } from '@/playback/youtube/engine';
import { getInnertube } from '@/playback/youtube/innertube';
import { CLIENT_ATTEMPTS, resolvePlayer, usesWebPo, type PlayerClientName } from '@/playback/youtube/resolver';
import { botguard } from '@/playback/youtube/botguard';
import { nativeCall, nativeDeckId } from './ios';

/** AVFoundation accepts progressive AAC audio; SABR/DASH remain on the browser engine. */
export async function loadIOSAudio(
  audio: HTMLAudioElement, videoId: string, startSec: number, autoplay: boolean, stillCurrent: () => void,
): Promise<LoadedTrack> {
  const yt = await getInnertube();
  const skip = new Set<PlayerClientName>();
  let failure: unknown = new Error('YouTube did not offer a playable AAC stream');
  for (let attempt = 0; attempt < CLIENT_ATTEMPTS; attempt++) {
    stillCurrent();
    try {
      const { info, client } = await resolvePlayer(yt, videoId, skip);
      skip.add(client);
      const formats = (info.streaming_data?.adaptive_formats ?? [])
        .filter((f) => f.has_audio && !f.has_video && f.mime_type.includes('mp4') && (f.url || f.signature_cipher || f.cipher))
        .sort((a, b) => b.bitrate - a.bitrate);
      const format = formats[0];
      if (!format) continue;
      const url = new URL(await format.decipher(yt.session.player));
      const pot = usesWebPo(client) ? await botguard.mint(videoId) : undefined;
      if (pot) url.searchParams.set('pot', pot);
      stillCurrent();
      const basic = info.basic_info;
      await nativeCall('audio.load', {
        id: nativeDeckId(audio), url: url.toString(), startSec, autoplay, videoId,
        title: basic.title ?? '', artist: basic.author ?? '',
        artwork: basic.thumbnail?.[0]?.url ?? null,
      });
      stillCurrent();
      return {
        videoId, title: basic.title ?? '', author: basic.author ?? '', durationSec: basic.duration ?? audio.duration,
        thumbnails: [...(basic.thumbnail ?? [])].sort((a, b) => b.width - a.width),
        client, format: `${format.itag} AAC ${Math.round(format.bitrate / 1000)}kbps · AVPlayer`,
        loudnessDb: info.player_config?.audio_config?.loudness_db ?? null,
      };
    } catch (error) {
      stillCurrent();
      failure = error;
    }
  }
  throw failure;
}
