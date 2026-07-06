import { useEffect, useState } from 'react';
import {
  getChatSession,
  subscribeToBridgeSessionEvents,
} from '../services/askUiBridgeClient';
import {
  getInitialChatSessionState,
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
    setChatSessionState({
      status: 'loading',
    });

    getChatSession(sessionId, clientId).then(
      (snapshot) => {
        if (!isCurrent) {
          return;
        }

        setChatSessionState(getInitialChatSessionState(snapshot));
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

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

        setChatSessionState((state) =>
          reduceChatSessionBridgeEvent(state, event),
        );
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
