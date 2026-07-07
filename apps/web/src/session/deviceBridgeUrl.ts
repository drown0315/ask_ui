import { resolveBridgeOrigin } from '../services/bridgeHttp.ts';

export function getDeviceWebSocketUrl(
  sessionId: string,
  envOrigin?: string,
  options?: {
    debugVideo?: 'fixture';
  },
): string {
  const url = new URL(resolveBridgeOrigin(envOrigin));
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.pathname = `/api/sessions/${encodeURIComponent(sessionId)}/device`;
  url.search = '';
  if (options?.debugVideo) {
    url.searchParams.set('debugVideo', options.debugVideo);
  }
  url.hash = '';
  return url.toString();
}
