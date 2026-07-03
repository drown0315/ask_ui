export type CreateBridgeSessionRequest = {
  vmServiceUri: string;
  projectRoot: string;
};

export type CreateBridgeSessionResponse = {
  sessionId: string;
};

export type WidgetTreeNodeResponse = {
  id: string;
  label: string;
  children: WidgetTreeNodeResponse[];
};

export type GetWidgetTreeResponse = {
  root: WidgetTreeNodeResponse;
};

export type HotReloadSessionResponse = {
  status: 'ok';
  message?: string;
  reloadReport?: Record<string, unknown>;
};

export type HotRestartSessionResponse = {
  status: 'ok';
  message?: string;
};

export type SelectWidgetModeResponse = {
  status: 'ok';
  enabled: boolean;
  message?: string;
};

export type SelectWidgetModeStatusResponse = {
  status: 'ok';
  known: boolean;
  enabled?: boolean;
};

const defaultBridgeOrigin = 'http://127.0.0.1:8787';

export class BridgeRequestError extends Error {
  readonly code?: string;

  constructor(message: string, code?: string) {
    super(message);
    this.name = 'BridgeRequestError';
    this.code = code;
  }
}

/**
 * Return the bridge origin used by web requests.
 *
 * Args:
 * - `envOrigin`: Optional value from `VITE_ASK_UI_BRIDGE_ORIGIN`. Empty or
 *   whitespace-only values mean the web page should use the local Dart bridge
 *   default.
 *
 * Returns:
 * A normalized origin without trailing slashes.
 *
 * Example:
 * `undefined` returns `http://127.0.0.1:8787`; `http://localhost:9000/`
 * returns `http://localhost:9000`.
 */
export function resolveBridgeOrigin(envOrigin: string | undefined): string {
  const trimmedOrigin = envOrigin?.trim().replace(/\/+$/, '');

  if (!trimmedOrigin) {
    return defaultBridgeOrigin;
  }

  return trimmedOrigin;
}

/**
 * Decode a bridge HTTP response as JSON and normalize empty response failures.
 *
 * Args:
 * - `response`: Fetch response returned by the bridge request.
 * - `fallbackMessage`: User-facing action message used when the response body
 *   is empty or not JSON.
 *
 * Returns:
 * Parsed JSON object from the bridge. The returned object may include bridge
 * error fields such as `error` or `message`.
 *
 * Example:
 * A 404 HTML or empty response from the web dev server becomes
 * `Failed to create Ask UI bridge session: empty response` instead of a raw
 * browser JSON parse error.
 */
export async function parseBridgeJsonResponse<T>(
  response: Response,
  fallbackMessage: string,
): Promise<T & { error?: string; message?: string }> {
  const text = await response.text();

  if (!text.trim()) {
    throw new Error(`${fallbackMessage}: empty response`);
  }

  try {
    return JSON.parse(text) as T & { error?: string };
  } catch {
    throw new Error(`${fallbackMessage}: non-JSON response`);
  }
}

const bridgeOrigin = resolveBridgeOrigin(import.meta.env?.VITE_ASK_UI_BRIDGE_ORIGIN);

/**
 * Create or reuse one bridge session for a running Flutter app target.
 *
 * Args:
 * - `request`: VM Service URI and project root read from the page URL.
 *
 * Returns:
 * The bridge session id for that target. The Dart bridge may return an existing
 * session id when another tab already opened the same target.
 *
 * Example:
 * Passing `ws://127.0.0.1:12345/ws` and `/Users/example/app` returns a
 * response such as `{sessionId: 'session-1'}`.
 */
export async function createBridgeSession(
  request: CreateBridgeSessionRequest,
): Promise<CreateBridgeSessionResponse> {
  const response = await fetch(`${bridgeOrigin}/api/sessions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify(request),
  });

  const body = await parseBridgeJsonResponse<Partial<CreateBridgeSessionResponse>>(
    response,
    'Failed to create Ask UI bridge session',
  );

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to create Ask UI bridge session',
      body.error,
    );
  }

  if (!body.sessionId) {
    throw new Error('Bridge session response did not include sessionId');
  }

  return {
    sessionId: body.sessionId,
  };
}

/**
 * Fetch the normalized Flutter Widget Tree for one bridge session.
 *
 * Args:
 * - `sessionId`: Session id returned by `createBridgeSession`.
 *
 * Returns:
 * A root `WidgetTreeNodeResponse` whose descendants are already normalized by
 * the bridge into `id`, `label`, and `children`.
 *
 * Example:
 * `getWidgetTree('session-1')` calls
 * `/api/sessions/session-1/widget-tree` and returns the current Inspector
 * summary tree snapshot.
 */
export async function getWidgetTree(
  sessionId: string,
): Promise<GetWidgetTreeResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/widget-tree`,
  );

  const body = await parseBridgeJsonResponse<Partial<GetWidgetTreeResponse>>(
    response,
    'Failed to fetch Flutter Widget Tree',
  );

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to fetch Flutter Widget Tree',
      body.error,
    );
  }

  if (!body.root) {
    throw new Error('Widget Tree response did not include root');
  }

  return {
    root: body.root,
  };
}

/**
 * Run Flutter hot reload for one bridge session.
 *
 * Args:
 * - `sessionId`: Existing bridge session id for the running Flutter app.
 *
 * Returns:
 * The bridge action response. On success the web UI should refresh the Widget
 * Tree because Inspector node ids belong to the previous snapshot.
 *
 * Example:
 * `hotReloadSession('session-1')` calls
 * `/api/sessions/session-1/hot-reload` and returns `{status: 'ok'}`.
 */
export async function hotReloadSession(
  sessionId: string,
): Promise<HotReloadSessionResponse> {
  return postSessionAction<HotReloadSessionResponse>(
    sessionId,
    'hot-reload',
    'Failed to hot reload Flutter app',
  );
}

/**
 * Run Flutter hot restart for one bridge session when the bridge supports it.
 *
 * Args:
 * - `sessionId`: Existing bridge session id for the running Flutter app.
 *
 * Returns:
 * The bridge action response. Unsupported sessions reject with the bridge
 * message, for example `Hot restart is not available for this bridge session.`
 */
export async function hotRestartSession(
  sessionId: string,
): Promise<HotRestartSessionResponse> {
  return postSessionAction<HotRestartSessionResponse>(
    sessionId,
    'hot-restart',
    'Failed to hot restart Flutter app',
  );
}

/**
 * Enable or disable Flutter Inspector Select Widget mode for one session.
 *
 * Args:
 * - `sessionId`: Existing bridge session id for the running Flutter app.
 * - `enabled`: `true` asks Flutter Inspector to show Select Widget mode;
 *   `false` hides it.
 *
 * Returns:
 * The bridge action response including the enabled state accepted by the
 * bridge.
 */
export async function setSelectWidgetMode(
  sessionId: string,
  enabled: boolean,
): Promise<SelectWidgetModeResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/select-widget-mode`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({ enabled }),
    },
  );

  const body = await parseBridgeJsonResponse<Partial<SelectWidgetModeResponse>>(
    response,
    'Failed to set Select Widget mode',
  );

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to set Select Widget mode',
      body.error,
    );
  }

  if (body.status !== 'ok' || typeof body.enabled !== 'boolean') {
    throw new Error('Select Widget mode response did not include enabled state');
  }

  return body as SelectWidgetModeResponse;
}

/**
 * Fetch the last Select Widget mode state observed by the Dart bridge.
 *
 * Args:
 * - `sessionId`: Existing bridge session id for the running Flutter app.
 *
 * Returns:
 * `{known: false}` when the bridge has not observed a Flutter Inspector state
 * event yet. Once known, `enabled` mirrors the current Inspector mode reported
 * by the app, including changes made by DevTools or another VM Service client.
 */
export async function getSelectWidgetModeStatus(
  sessionId: string,
): Promise<SelectWidgetModeStatusResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/select-widget-mode`,
  );

  const body = await parseBridgeJsonResponse<
    Partial<SelectWidgetModeStatusResponse>
  >(response, 'Failed to fetch Select Widget mode status');

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to fetch Select Widget mode status',
      body.error,
    );
  }

  if (body.status !== 'ok' || typeof body.known !== 'boolean') {
    throw new Error('Select Widget mode status response did not include known');
  }

  if (body.known && typeof body.enabled !== 'boolean') {
    throw new Error('Known Select Widget mode status did not include enabled');
  }

  return body as SelectWidgetModeStatusResponse;
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
    throw new BridgeRequestError(
      body.message ?? body.error ?? fallbackMessage,
      body.error,
    );
  }

  if (body.status !== 'ok') {
    throw new Error(`${fallbackMessage}: missing ok status`);
  }

  return body as T;
}
