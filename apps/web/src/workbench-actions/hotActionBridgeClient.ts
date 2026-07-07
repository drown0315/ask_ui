import {
  bridgeOrigin,
  bridgeRequestError,
  parseBridgeJsonResponse,
} from '../services/bridgeHttp.ts';
import type {
  HotReloadSessionResponse,
  HotRestartSessionResponse,
} from '../services/bridgeTypes.ts';

export async function hotReloadSession(
  sessionId: string,
): Promise<HotReloadSessionResponse> {
  return postSessionAction<HotReloadSessionResponse>(
    sessionId,
    'hot-reload',
    'Failed to hot reload Flutter app',
  );
}

export async function hotRestartSession(
  sessionId: string,
): Promise<HotRestartSessionResponse> {
  return postSessionAction<HotRestartSessionResponse>(
    sessionId,
    'hot-restart',
    'Failed to hot restart Flutter app',
  );
}

async function postSessionAction<T extends { status: 'ok' }>(
  sessionId: string,
  action: 'hot-reload' | 'hot-restart',
  fallbackMessage: string,
): Promise<T> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/${action}`,
    {
      method: 'POST',
    },
  );

  const body = await parseBridgeJsonResponse<Partial<T>>(
    response,
    fallbackMessage,
  );

  if (!response.ok) {
    throw bridgeRequestError(body, fallbackMessage);
  }

  if (body.status !== 'ok') {
    throw new Error(`${fallbackMessage}: missing ok status`);
  }

  return body as T;
}
