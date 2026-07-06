export type CreateBridgeSessionRequest = {
  vmServiceUri: string;
  projectRoot: string;
  deviceId: string;
  clientId?: string;
};

export type CreateBridgeSessionResponse = {
  sessionId: string;
  targetDevice?: {
    id: string;
    displayName?: string;
  };
  readOnly: boolean;
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

export type WidgetSelectionResponse = {
  status: 'ok';
  widgetId: string;
  message?: string;
};

export type AgentStatusResponse =
  | 'waiting_for_agent'
  | 'agent_ready'
  | 'agent_working';

export type ChatMessageResponse = {
  id: string;
  role: 'user' | 'agent' | 'system';
  text: string;
};

export type GetChatSessionResponse = {
  status: 'ok';
  agentStatus: AgentStatusResponse;
  readOnly: boolean;
  messages: ChatMessageResponse[];
};

export type BridgeSessionEvent =
  | {
      type: 'select_widget_mode_snapshot' | 'select_widget_mode_changed';
      sessionId: string;
      payload: {
        known?: boolean;
        enabled?: boolean;
      };
    }
  | {
      type: 'chat_snapshot';
      sessionId: string;
      payload: {
        agentStatus: AgentStatusResponse;
        messages: ChatMessageResponse[];
      };
    }
  | {
      type: 'agent_status_changed';
      sessionId: string;
      payload: {
        agentStatus: AgentStatusResponse;
      };
    }
  | {
      type: 'chat_history_changed';
      sessionId: string;
      payload: {
        messages: ChatMessageResponse[];
      };
    };

export type SelectWidgetBridgeSessionEvent = Extract<
  BridgeSessionEvent,
  { type: 'select_widget_mode_snapshot' | 'select_widget_mode_changed' }
>;

export type ChatBridgeSessionEvent = Exclude<
  BridgeSessionEvent,
  SelectWidgetBridgeSessionEvent
>;

type LegacyBridgeSessionEvent = {
  type:
    | 'select_widget_mode_snapshot'
    | 'select_widget_mode_changed'
    | 'chat_snapshot'
    | 'agent_status_changed'
    | 'chat_history_changed';
  sessionId: string;
  payload: Record<string, unknown>;
};

type BridgeSessionEventSource = Pick<
  EventSource,
  'addEventListener' | 'close'
>;

type SubscribeToBridgeSessionEventsOptions = {
  createEventSource?: (url: string) => BridgeSessionEventSource;
  onDisconnect?: () => void;
  onInvalidEvent?: (error: Error) => void;
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
 * Build the bridge-owned Live App Surface Device WebSocket URL for one session.
 *
 * Args:
 * - `sessionId`: Existing bridge session id. The URL does not include
 *   `deviceId` because the bridge session already owns the Target Device
 *   binding.
 * - `envOrigin`: Optional bridge HTTP origin. When omitted, the local bridge
 *   default is used.
 *
 * Returns:
 * A `ws:` or `wss:` URL under `/api/sessions/:sessionId/device`.
 *
 * Example:
 * `getDeviceWebSocketUrl('session-1', 'http://127.0.0.1:8787')`
 * returns `ws://127.0.0.1:8787/api/sessions/session-1/device`.
 */
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

export const bridgeOrigin = resolveBridgeOrigin(
  import.meta.env?.VITE_ASK_UI_BRIDGE_ORIGIN,
);

/**
 * Create or reuse one bridge session for a running Flutter app target.
 *
 * Args:
 * - `request`: VM Service URI, project root, and device id read from the page
 *   URL.
 *
 * Returns:
 * The bridge session id for that target. The Dart bridge may return an existing
 * session id when another tab already opened the same target.
 *
 * Example:
 * Passing `ws://127.0.0.1:12345/ws`, `/Users/example/app`, and
 * `19271FDF6007TY` returns a response such as `{sessionId: 'session-1'}`.
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

  const responseBody: CreateBridgeSessionResponse = {
    sessionId: body.sessionId,
    readOnly: body.readOnly === true,
  };

  if (
    body.targetDevice &&
    typeof body.targetDevice === 'object' &&
    'id' in body.targetDevice &&
    typeof body.targetDevice.id === 'string'
  ) {
    responseBody.targetDevice = {
      id: body.targetDevice.id,
      displayName:
        'displayName' in body.targetDevice &&
        typeof body.targetDevice.displayName === 'string'
          ? body.targetDevice.displayName
          : undefined,
    };
  }

  return responseBody;
}

/**
 * Fetch the current Bridge Session Chat snapshot.
 *
 * Args:
 * - `sessionId`: Existing bridge session id.
 * - `clientId`: Browser-tab id used by the bridge to report read-only mode for
 *   secondary tabs.
 *
 * Returns:
 * Chat History, Agent Status, and whether this browser client is read-only.
 */
export async function getChatSession(
  sessionId: string,
  clientId: string | null = null,
): Promise<GetChatSessionResponse> {
  const url = new URL(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/chat`,
  );
  if (clientId) {
    url.searchParams.set('clientId', clientId);
  }

  const response = await fetch(url.toString());
  const body = await parseBridgeJsonResponse<Partial<GetChatSessionResponse>>(
    response,
    'Failed to load Chat History',
  );

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to load Chat History',
      body.error,
    );
  }

  if (
    body.status !== 'ok' ||
    !isAgentStatusResponse(body.agentStatus) ||
    !Array.isArray(body.messages)
  ) {
    throw new Error('Chat response did not include Chat History');
  }

  return {
    status: 'ok',
    agentStatus: body.agentStatus,
    readOnly: body.readOnly === true,
    messages: body.messages,
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

/**
 * Select one Flutter Inspector widget object from the web Widget Tree.
 *
 * Args:
 * - `sessionId`: Existing bridge session id for the running Flutter app.
 * - `widgetId`: Inspector object id from the current Widget Tree snapshot.
 *
 * Returns:
 * The bridge response containing the selected widget id. Stale ids reject with
 * the bridge error message.
 *
 * Example:
 * `selectWidgetById('session-1', 'inspector-2')` calls
 * `/api/sessions/session-1/widget-selection` with
 * `{widgetId: 'inspector-2'}`.
 */
export async function selectWidgetById(
  sessionId: string,
  widgetId: string,
): Promise<WidgetSelectionResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/widget-selection`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({ widgetId }),
    },
  );

  const body = await parseBridgeJsonResponse<Partial<WidgetSelectionResponse>>(
    response,
    'Failed to select Flutter widget',
  );

  if (!response.ok) {
    throw new BridgeRequestError(
      body.message ?? body.error ?? 'Failed to select Flutter widget',
      body.error,
    );
  }

  if (body.status !== 'ok' || typeof body.widgetId !== 'string') {
    throw new Error('Widget selection response did not include widgetId');
  }

  return body as WidgetSelectionResponse;
}

/**
 * Subscribe to bridge events for one running Flutter app session.
 *
 * Args:
 * - `sessionId`: Existing bridge session id returned by `createBridgeSession`.
 * - `onEvent`: Called for each parsed `bridge_session_event` SSE message.
 * - `options.createEventSource`: Optional factory used by tests. When omitted,
 *   the browser's native `EventSource` opens the Dart bridge stream.
 * - `options.onInvalidEvent`: Optional callback for malformed event payloads.
 *   Invalid payloads are ignored so one bad event does not stop later updates.
 *
 * Returns:
 * An object with `close`, which disconnects this browser tab from the SSE
 * stream. The browser handles network reconnects while the subscription is
 * open.
 *
 * Example:
 * Subscribing to `session-1` opens
 * `/api/sessions/session-1/events` and receives
 * `select_widget_mode_snapshot` followed by later
 * `select_widget_mode_changed` events.
 */
export function subscribeToBridgeSessionEvents(
  sessionId: string,
  onEvent: (event: BridgeSessionEvent) => void,
  options: SubscribeToBridgeSessionEventsOptions = {},
): { close: () => void } {
  const source =
    options.createEventSource?.(
      `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/events`,
    ) ??
    new EventSource(
      `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/events`,
    );

  source.addEventListener('bridge_session_event', (message) => {
    try {
      onEvent(parseBridgeSessionEvent((message as MessageEvent).data));
    } catch (error) {
      options.onInvalidEvent?.(
        error instanceof Error ? error : new Error('Invalid bridge event'),
      );
    }
  });
  source.addEventListener('error', () => {
    options.onDisconnect?.();
  });

  return {
    close() {
      source.close();
    },
  };
}

/**
 * Parse one SSE message payload into a bridge session event.
 *
 * Args:
 * - `rawData`: String from the EventSource `data` field. Empty, non-JSON, or
 *   unknown event shapes throw so callers can ignore malformed updates without
 *   changing UI state.
 *
 * Returns:
 * A `BridgeSessionEvent` with a supported `type`, a `sessionId`, and a payload
 * object. The payload is intentionally loose because different event types
 * carry different fields.
 *
 * Example:
 * `{"type":"select_widget_mode_changed","sessionId":"session-1","payload":{"enabled":true}}`
 * becomes a typed event that can update the Select Widget toggle.
 */
function parseBridgeSessionEvent(rawData: string): BridgeSessionEvent {
  const decoded = JSON.parse(rawData) as Partial<LegacyBridgeSessionEvent>;

  if (!decoded.type || !isBridgeSessionEventType(decoded.type)) {
    throw new Error('Bridge session event has an unknown type');
  }

  if (typeof decoded.sessionId !== 'string') {
    throw new Error('Bridge session event did not include sessionId');
  }

  if (!decoded.payload || typeof decoded.payload !== 'object') {
    throw new Error('Bridge session event did not include payload');
  }

  validateBridgeSessionEventPayload(decoded as LegacyBridgeSessionEvent);

  return decoded as BridgeSessionEvent;
}

function isBridgeSessionEventType(
  type: string,
): type is LegacyBridgeSessionEvent['type'] {
  return (
    type === 'select_widget_mode_snapshot' ||
    type === 'select_widget_mode_changed' ||
    type === 'chat_snapshot' ||
    type === 'agent_status_changed' ||
    type === 'chat_history_changed'
  );
}

function validateBridgeSessionEventPayload(event: LegacyBridgeSessionEvent) {
  if (
    event.type === 'select_widget_mode_snapshot' ||
    event.type === 'select_widget_mode_changed'
  ) {
    return;
  }

  if (
    (event.type === 'chat_snapshot' ||
      event.type === 'agent_status_changed') &&
    !isAgentStatusResponse(event.payload.agentStatus)
  ) {
    throw new Error('Chat event did not include Agent Status');
  }

  if (
    (event.type === 'chat_snapshot' ||
      event.type === 'chat_history_changed') &&
    !Array.isArray(event.payload.messages)
  ) {
    throw new Error('Chat event did not include Chat History');
  }
}

function isAgentStatusResponse(value: unknown): value is AgentStatusResponse {
  return (
    value === 'waiting_for_agent' ||
    value === 'agent_ready' ||
    value === 'agent_working'
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
