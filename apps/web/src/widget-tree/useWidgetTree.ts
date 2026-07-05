import { useCallback, useEffect, useState } from 'react';
import { getWidgetTree } from '../services/askUiBridgeClient';
import type { WidgetTreeLoadState } from '../types/bridgeSession';

export function getWidgetTreeErrorMessage(error: unknown): string {
  return error instanceof Error
    ? error.message
    : 'Failed to fetch Flutter Widget Tree';
}

/**
 * Load and refresh the Flutter Widget Tree for the ready bridge session.
 *
 * Args:
 * - `sessionId`: Ready bridge session id. `null` means the Widget Tree should
 *   stay in a loading placeholder until a session exists.
 *
 * Returns:
 * The current Widget Tree load state, a setter used by workbench actions, and a
 * refresh function that fetches the latest tree through the bridge.
 *
 * Example:
 * When `sessionId` becomes `session-1`, this hook fetches
 * `/api/sessions/session-1/widget-tree` and stores the loaded root.
 */
export function useWidgetTree(sessionId: string | null): {
  widgetTreeState: WidgetTreeLoadState;
  setWidgetTreeState: (state: WidgetTreeLoadState) => void;
  refreshWidgetTree: () => Promise<void>;
} {
  const [widgetTreeState, setWidgetTreeState] = useState<WidgetTreeLoadState>({
    status: 'loading',
  });

  const refreshWidgetTree = useCallback(async () => {
    if (sessionId === null) {
      return;
    }

    setWidgetTreeState({
      status: 'loading',
    });

    try {
      const { root } = await getWidgetTree(sessionId);
      setWidgetTreeState({
        status: 'loaded',
        root,
      });
    } catch (error: unknown) {
      setWidgetTreeState({
        status: 'error',
        message: getWidgetTreeErrorMessage(error),
      });
      throw error;
    }
  }, [sessionId]);

  useEffect(() => {
    if (sessionId === null) {
      setWidgetTreeState({
        status: 'loading',
      });
      return;
    }

    let isCurrent = true;
    setWidgetTreeState({
      status: 'loading',
    });

    getWidgetTree(sessionId).then(
      ({ root }) => {
        if (!isCurrent) {
          return;
        }

        setWidgetTreeState({
          status: 'loaded',
          root,
        });
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

        setWidgetTreeState({
          status: 'error',
          message: getWidgetTreeErrorMessage(error),
        });
      },
    );

    return () => {
      isCurrent = false;
    };
  }, [sessionId]);

  return {
    widgetTreeState,
    setWidgetTreeState,
    refreshWidgetTree,
  };
}
