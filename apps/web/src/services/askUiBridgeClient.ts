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

const defaultBridgeOrigin = 'http://127.0.0.1:8787';

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
    throw new Error(
      body.message ?? body.error ?? 'Failed to create Ask UI bridge session',
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
    throw new Error(
      body.message ?? body.error ?? 'Failed to fetch Flutter Widget Tree',
    );
  }

  if (!body.root) {
    throw new Error('Widget Tree response did not include root');
  }

  return {
    root: body.root,
  };
}
