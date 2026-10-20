import * as music from '@/data/music/api';
import { queryClient } from '@/lib/queryClient';
import { extensionQueryKey } from '@/extension/useExtension';
import { detectIOSHost } from './bridge';
import { createIOSAudio, nativeCall } from './ios';
import { loadIOSAudio } from './engine';

queryClient.setQueryData(extensionQueryKey, detectIOSHost());
const decks = [createIOSAudio(), createIOSAudio()] as const;
const generations: [number, number] = [0, 0];
const continuations = new Map<string, () => Promise<unknown>>();
let sequence = 0;

function paged(data: unknown, next: (() => Promise<unknown>) | null): { data: unknown; cursor: string | null } {
  const cursor = next ? String(++sequence) : null;
  if (cursor && next) continuations.set(cursor, next);
  if (continuations.size > 100) continuations.delete(continuations.keys().next().value!);
  return { data, cursor };
}

export async function request(method: string, p: Record<string, string | number>): Promise<unknown> {
  switch (method) {
    case 'home': { const page = await music.fetchHome(); return paged(page.data, page.next); }
    case 'explore': return music.fetchExplore();
    case 'search': return music.fetchSearch(String(p.query));
    case 'album': return music.fetchAlbum(String(p.id));
    case 'artist': return music.fetchArtist(String(p.id));
    case 'playlist': { const page = await music.fetchPlaylist(String(p.id)); return { ...page.page, cursor: paged([], page.more).cursor }; }
    case 'browse': return music.fetchBrowse({ browseId: String(p.id), params: p.params ? String(p.params) : null });
    case 'more': {
      const key = String(p.cursor), next = continuations.get(key);
      if (!next) throw new Error('This page expired. Pull to refresh.');
      const page = await next() as music.Paged<unknown>;
      continuations.delete(key);
      return paged(page.data, page.next);
    }
    case 'cancel': {
      const deck = Number(p.deck);
      if (deck !== 0 && deck !== 1) throw new Error('Invalid audio deck');
      generations[deck]++; return {};
    }
    case 'resolve': {
      const deck = Number(p.deck);
      if (deck !== 0 && deck !== 1) throw new Error('Invalid audio deck');
      const token = ++generations[deck];
      const current = () => { if (generations[deck] !== token) throw new Error('Superseded'); };
      return loadIOSAudio(decks[deck], String(p.id), 0, false, current);
    }
    default: throw new Error(`Unknown catalogue method: ${method}`);
  }
}

Object.assign(window, { __bcService: request });
void nativeCall('service.ready');
