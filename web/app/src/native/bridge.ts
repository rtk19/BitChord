import { BRIDGE_PROTOCOL, BridgeCallError, type Bridge, type DetectedExtension } from '@bitchord/shared/bridge';
import { isIOSApp, nativeCall } from './ios';

/** Native networking replaces extension-only HTTP access; never advertise unimplemented account integrations. */
export function detectIOSHost(): DetectedExtension | null {
  if (!isIOSApp()) return null;
  const bridge: Bridge = {
    transport: 'relay',
    async call(method, params) {
      if (method === 'ping') return info as never;
      if (method === 'yt.fetch' || method === 'lyrics.fetch' || method === 'addon.fetch') {
        if ('auth' in params && params.auth) throw new BridgeCallError('unauthenticated', 'YouTube sign-in is not available in this iOS build');
        return nativeCall('http.fetch', params as unknown as Record<string, unknown>) as never;
      }
      if (method === 'lyrics.permissions') return { granted: (params as { origins: string[] }).origins } as never;
      if (method === 'lyrics.requestPermissions') return {} as never;
      throw new BridgeCallError('unsupported', `${method} is not available in this iOS build`);
    },
    subscribe: () => () => {},
  };
  const info: DetectedExtension['info'] = { version: 'ios-0.1', protocol: BRIDGE_PROTOCOL, browser: 'chromium', capabilities: ['yt', 'lyrics', 'addon'] };
  return { bridge, info };
}
