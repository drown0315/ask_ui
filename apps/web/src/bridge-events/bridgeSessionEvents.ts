import { bridgeOrigin } from '../services/bridgeHttp.ts';
import type {
  AgentStatusResponse,
  BridgeSessionEvent,
} from '../services/bridgeTypes.ts';
import { isAgentStatusResponse } from '../services/bridgeTypes.ts';

type LegacyBridgeSessionEvent = {
  type:
    | 'select_widget_mode_snapshot'
    | 'select_widget_mode_changed'
    | 'widget_selection_changed'
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

export function parseBridgeSessionEvent(rawData: string): BridgeSessionEvent {
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
    type === 'widget_selection_changed' ||
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
    event.type === 'widget_selection_changed' &&
    typeof event.payload.widgetId !== 'string'
  ) {
    throw new Error('Widget Selection event did not include widgetId');
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

export function isChatAgentStatusPayload(
  value: unknown,
): value is AgentStatusResponse {
  return isAgentStatusResponse(value);
}
