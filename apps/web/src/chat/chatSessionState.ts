import type {
  BridgeSessionEvent,
  ChatMessageResponse,
  GetChatSessionResponse,
} from '../services/askUiBridgeClient';

export type ChatSessionState =
  | {
      status: 'idle' | 'loading';
    }
  | {
      status: 'ready';
      agentStatus: GetChatSessionResponse['agentStatus'];
      readOnly: boolean;
      connectionWarning: string | null;
      messages: ChatMessageResponse[];
    }
  | {
      status: 'error';
      message: string;
    };

export function getInitialChatSessionState(
  snapshot: GetChatSessionResponse,
): ChatSessionState {
  return {
    status: 'ready',
    agentStatus: snapshot.agentStatus,
    readOnly: snapshot.readOnly,
    connectionWarning: null,
    messages: snapshot.messages,
  };
}

export function getInitialChatSessionStateWithQueuedEvents(
  snapshot: GetChatSessionResponse,
  queuedEvents: BridgeSessionEvent[],
): ChatSessionState {
  return queuedEvents.reduce(
    reduceChatSessionBridgeEvent,
    getInitialChatSessionState(snapshot),
  );
}

export function reduceChatSessionBridgeEvent(
  state: ChatSessionState,
  event: BridgeSessionEvent,
): ChatSessionState {
  if (state.status !== 'ready') {
    return state;
  }

  if (event.type === 'chat_snapshot') {
    return {
      ...state,
      agentStatus: event.payload.agentStatus,
      messages: event.payload.messages,
      connectionWarning: null,
    };
  }

  if (event.type === 'agent_status_changed') {
    return {
      ...state,
      agentStatus: event.payload.agentStatus,
      connectionWarning: null,
    };
  }

  if (event.type === 'chat_history_changed') {
    return {
      ...state,
      messages: event.payload.messages,
      connectionWarning: null,
    };
  }

  return state;
}

export function reduceChatSessionDisconnected(
  state: ChatSessionState,
): ChatSessionState {
  if (state.status !== 'ready') {
    return state;
  }

  return {
    ...state,
    agentStatus: 'waiting_for_agent',
    connectionWarning: 'Bridge session events disconnected.',
  };
}

export function getAgentStatusLabel(
  status: GetChatSessionResponse['agentStatus'],
): string {
  if (status === 'agent_ready') {
    return 'Agent ready';
  }

  if (status === 'agent_working') {
    return 'Agent working';
  }

  return 'Waiting for agent';
}

/**
 * Return the Chat History rows visible in the Chat panel.
 *
 * The temporary `Agent working...` row is derived from Agent Status and is not
 * persisted in Bridge Session Chat History.
 */
export function getVisibleChatHistoryMessages(
  state: ChatSessionState,
): ChatMessageResponse[] {
  if (state.status !== 'ready') {
    return [];
  }

  if (state.agentStatus !== 'agent_working') {
    return state.messages;
  }

  return [
    ...state.messages,
    {
      id: 'agent-working-placeholder',
      role: 'agent',
      text: 'Agent working...',
    },
  ];
}
