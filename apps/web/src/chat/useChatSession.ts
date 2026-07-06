import { useEffect, useState } from 'react';
import {
  getChatSession,
  subscribeToBridgeSessionEvents,
  type BridgeSessionEvent,
} from '../services/askUiBridgeClient';
import {
  getInitialChatSessionStateWithQueuedEvents,
  reduceChatSessionBridgeEvent,
  reduceChatSessionDisconnected,
  type ChatSessionState,
} from './chatSessionState';

/**
 * Load and observe Chat state for the current Bridge Session.
 *
 * The hook first fetches the in-memory Bridge Session Chat snapshot, then
 * listens to the existing session SSE stream for Chat History and Agent Status
 * updates. It does not create a separate Chat socket.
 */
export function useChatSession({
  clientId,
  sessionId,
}: {
  clientId: string | null;
  sessionId: string | null;
}): ChatSessionState {
  const [chatSessionState, setChatSessionState] = useState<ChatSessionState>({
    status: 'idle',
  });

  useEffect(() => {
    if (sessionId === null) {
      setChatSessionState({
        status: 'idle',
      });
      return;
    }

    let isCurrent = true;
    let hasLoadedInitialSnapshot = false;
    let latestReadyChatSessionState: ChatSessionState | null = null;
    const queuedEvents: BridgeSessionEvent[] = [];
    setChatSessionState({
      status: 'loading',
    });

    getChatSession(sessionId, clientId).then(
      (snapshot) => {
        if (!isCurrent) {
          return;
        }

        latestReadyChatSessionState =
          getInitialChatSessionStateWithQueuedEvents(snapshot, queuedEvents);
        hasLoadedInitialSnapshot = true;
        setChatSessionState(latestReadyChatSessionState);
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

        hasLoadedInitialSnapshot = true;
        setChatSessionState({
          status: 'error',
          message:
            error instanceof Error
              ? error.message
              : 'Failed to load Chat History',
        });
      },
    );

    const subscription = subscribeToBridgeSessionEvents(
      sessionId,
      (event) => {
        if (!isCurrent || event.sessionId !== sessionId) {
          return;
        }

        if (!hasLoadedInitialSnapshot) {
          queuedEvents.push(event);
          return;
        }

        setChatSessionState((state) => {
          const currentState =
            state.status === 'ready' ? state : latestReadyChatSessionState;

          if (currentState === null) {
            return state;
          }

          const nextState = reduceChatSessionBridgeEvent(currentState, event);
          latestReadyChatSessionState = nextState;

          return nextState;
        });
      },
      {
        onDisconnect() {
          if (!isCurrent) {
            return;
          }

          setChatSessionState(reduceChatSessionDisconnected);
        },
      },
    );

    return () => {
      isCurrent = false;
      subscription.close();
    };
  }, [clientId, sessionId]);

  return chatSessionState;
}
