import { useCallback, useEffect, useRef, useState } from 'react';
import {
  BridgeRequestError,
  hotReloadSession,
  hotRestartSession,
  setSelectWidgetMode,
  subscribeToBridgeSessionEvents,
  type BridgeSessionEvent,
} from '../services/askUiBridgeClient';
import type { WidgetTreeLoadState } from '../types/bridgeSession';
import {
  initialTopBarActionState,
  markSessionActionUnavailable,
  toggleSelectWidgetMode,
  type TopBarActionState,
} from '../components/top-bar/topBarActions';

type UseWorkbenchActionsOptions = {
  sessionId: string | null;
  widgetTreeState: WidgetTreeLoadState;
  setWidgetTreeState: (state: WidgetTreeLoadState) => void;
  refreshWidgetTree: () => Promise<void>;
};

/**
 * Manage TopBar actions for the current bridge session.
 *
 * Args:
 * - `options.sessionId`: Ready bridge session id, or `null` before startup
 *   completes.
 * - `options.widgetTreeState`: Current Widget Tree state used for hot reload
 *   rollback when the reload action fails.
 * - `options.setWidgetTreeState`: Setter for action-driven Widget Tree loading
 *   and rollback states.
 * - `options.refreshWidgetTree`: Fetches a fresh Widget Tree snapshot.
 *
 * Returns:
 * TopBar action state and handlers for Select Widget, Hot Reload, and Hot
 * Restart buttons.
 *
 * Example:
 * Calling `handleHotReload` runs the bridge hot reload endpoint, refreshes the
 * Widget Tree on success, and restores the previous tree when reload fails.
 */
export function useWorkbenchActions(
  options: UseWorkbenchActionsOptions,
): {
  topBarActionState: TopBarActionState;
  handleToggleSelectWidget: () => void;
  handleHotReload: () => Promise<void>;
  handleHotRestart: () => Promise<void>;
} {
  const {
    sessionId,
    widgetTreeState,
    setWidgetTreeState,
    refreshWidgetTree,
  } = options;
  const [topBarActionState, setTopBarActionState] = useState<TopBarActionState>(
    initialTopBarActionState,
  );
  const selectWidgetSyncRef = useRef({
    didMount: false,
    previousActive: topBarActionState.isSelectWidgetActive,
    skipNextSync: false,
  });

  const syncSelectWidgetModeFromBridgeEvent = useCallback(
    (event: BridgeSessionEvent) => {
      if (
        event.sessionId !== sessionId ||
        (event.type !== 'select_widget_mode_snapshot' &&
          event.type !== 'select_widget_mode_changed') ||
        typeof event.payload.enabled !== 'boolean'
      ) {
        return;
      }

      const externalEnabled = event.payload.enabled;
      setTopBarActionState((state) => {
        if (state.isSelectWidgetActive === externalEnabled) {
          return state;
        }

        selectWidgetSyncRef.current.skipNextSync = true;
        return {
          ...state,
          isSelectWidgetActive: externalEnabled,
          selectWidget: {
            status: 'idle',
            message: externalEnabled
              ? 'Select Widget mode enabled.'
              : 'Select Widget mode disabled.',
          },
        };
      });
    },
    [sessionId],
  );

  useEffect(() => {
    if (!selectWidgetSyncRef.current.didMount) {
      selectWidgetSyncRef.current.didMount = true;
      selectWidgetSyncRef.current.previousActive =
        topBarActionState.isSelectWidgetActive;
      return;
    }

    if (selectWidgetSyncRef.current.skipNextSync) {
      selectWidgetSyncRef.current.skipNextSync = false;
      selectWidgetSyncRef.current.previousActive =
        topBarActionState.isSelectWidgetActive;
      return;
    }

    if (
      selectWidgetSyncRef.current.previousActive ===
      topBarActionState.isSelectWidgetActive
    ) {
      return;
    }

    selectWidgetSyncRef.current.previousActive =
      topBarActionState.isSelectWidgetActive;

    if (sessionId === null) {
      return;
    }

    let isCurrent = true;
    const enabled = topBarActionState.isSelectWidgetActive;

    setTopBarActionState((state) => ({
      ...state,
      selectWidget: {
        status: 'running',
      },
    }));

    setSelectWidgetMode(sessionId, enabled).then(
      () => {
        if (!isCurrent) {
          return;
        }

        setTopBarActionState((state) => ({
          ...state,
          selectWidget: {
            status: 'idle',
            message: enabled
              ? 'Select Widget mode enabled.'
              : 'Select Widget mode disabled.',
          },
        }));
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

        selectWidgetSyncRef.current.skipNextSync = true;
        setTopBarActionState((state) => ({
          ...state,
          isSelectWidgetActive: !enabled,
          selectWidget: {
            status: 'failed',
            message:
              error instanceof Error
                ? error.message
                : 'Failed to set Select Widget mode',
          },
        }));
      },
    );

    return () => {
      isCurrent = false;
    };
  }, [sessionId, topBarActionState.isSelectWidgetActive]);

  useEffect(() => {
    if (sessionId === null) {
      return;
    }

    const subscription = subscribeToBridgeSessionEvents(
      sessionId,
      syncSelectWidgetModeFromBridgeEvent,
    );

    return () => {
      subscription.close();
    };
  }, [sessionId, syncSelectWidgetModeFromBridgeEvent]);

  function handleToggleSelectWidget() {
    if (sessionId === null) {
      setTopBarActionState((state) => ({
        ...state,
        selectWidget: {
          status: 'failed',
          message: 'Bridge session required before Select Widget mode.',
        },
      }));
      return;
    }

    setTopBarActionState(toggleSelectWidgetMode);
  }

  async function handleHotReload() {
    if (sessionId === null) {
      setTopBarActionState((state) =>
        markSessionActionUnavailable(state, 'hotReload'),
      );
      return;
    }

    const previousWidgetTree = widgetTreeState;

    setTopBarActionState((state) => ({
      ...state,
      hotReload: {
        status: 'running',
      },
    }));
    setWidgetTreeState({
      status: 'loading',
    });

    try {
      await hotReloadSession(sessionId);
    } catch (error: unknown) {
      setTopBarActionState((state) => ({
        ...state,
        hotReload: {
          status: 'failed',
          message: error instanceof Error ? error.message : 'Hot reload failed',
        },
      }));
      setWidgetTreeState(previousWidgetTree);
      return;
    }

    try {
      await refreshWidgetTree();
      setTopBarActionState((state) => ({
        ...state,
        hotReload: {
          status: 'idle',
          message: 'Hot reload completed.',
        },
      }));
    } catch (error: unknown) {
      setWidgetTreeState({
        status: 'error',
        message:
          error instanceof Error
            ? error.message
            : 'Failed to fetch Flutter Widget Tree',
      });
      setTopBarActionState((state) => ({
        ...state,
        hotReload: {
          status: 'idle',
          message: 'Hot reload completed, but Widget Tree refresh failed.',
        },
      }));
    }
  }

  async function handleHotRestart() {
    if (sessionId === null) {
      setTopBarActionState((state) =>
        markSessionActionUnavailable(state, 'hotRestart'),
      );
      return;
    }

    setTopBarActionState((state) => ({
      ...state,
      hotRestart: {
        status: 'running',
      },
    }));

    try {
      await hotRestartSession(sessionId);
      setTopBarActionState((state) => ({
        ...state,
        hotRestart: {
          status: 'idle',
          message: 'Hot restart completed.',
        },
      }));
    } catch (error: unknown) {
      const isUnsupported =
        error instanceof BridgeRequestError &&
        error.code === 'hot_restart_not_supported_for_session';

      setTopBarActionState((state) => ({
        ...state,
        hotRestart: {
          status: isUnsupported ? 'unsupported' : 'failed',
          message: error instanceof Error ? error.message : 'Hot restart failed',
        },
      }));
    }
  }

  return {
    topBarActionState,
    handleToggleSelectWidget,
    handleHotReload,
    handleHotRestart,
  };
}
