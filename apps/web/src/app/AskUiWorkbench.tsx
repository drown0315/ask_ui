import {
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type PointerEvent,
} from 'react';
import { DeviceStage } from '../components/device-stage/DeviceStage';
import { SelectionNotesPanel } from '../components/selection-notes/SelectionNotesPanel';
import { TopBar } from '../components/top-bar/TopBar';
import {
  getTopBarStatusMessage,
  initialTopBarActionState,
  markSessionActionUnavailable,
  toggleSelectWidgetMode,
  type TopBarActionState,
} from '../components/top-bar/topBarActions';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';
import {
  findWidgetTreeMatches,
  getNextMatchIndex,
  getPreviousMatchIndex,
} from '../components/widget-tree/widgetTreeSearch';
import {
  BridgeRequestError,
  createBridgeSession,
  getWidgetTree,
  hotReloadSession,
  hotRestartSession,
  selectWidgetById,
  setSelectWidgetMode,
  subscribeToBridgeSessionEvents,
  type BridgeSessionEvent,
} from '../services/askUiBridgeClient';
import { readSessionBootstrap } from '../session/sessionBootstrap';
import type { BridgeSessionState, WidgetTreeLoadState } from '../types/bridgeSession';

const minWidgetTreeWidth = 260;
const maxWidgetTreeWidth = 520;
const defaultWidgetTreeWidth = 360;

function clampPanelWidth(width: number) {
  return Math.min(maxWidgetTreeWidth, Math.max(minWidgetTreeWidth, width));
}

export function AskUiWorkbench() {
  const [widgetTreeWidth, setWidgetTreeWidth] = useState(defaultWidgetTreeWidth);
  const [topBarActionState, setTopBarActionState] = useState<TopBarActionState>(
    initialTopBarActionState,
  );
  const [selectedWidgetId, setSelectedWidgetId] = useState<string | null>(null);
  const [widgetSelectionError, setWidgetSelectionError] = useState<string | null>(
    null,
  );
  const [widgetSearchQuery, setWidgetSearchQuery] = useState('');
  const [widgetSearchActiveIndex, setWidgetSearchActiveIndex] = useState(-1);
  const [bridgeSessionState, setBridgeSessionState] = useState<BridgeSessionState>(() => {
    const bootstrap = readSessionBootstrap(window.location.href);

    if (bootstrap.status === 'incomplete') {
      return {
        status: 'incomplete',
        missing: bootstrap.missing,
      };
    }

    return {
      status: 'creating',
    };
  });
  const dragStateRef = useRef<{
    pointerId: number;
    startX: number;
    startWidth: number;
  } | null>(null);
  const selectWidgetSyncRef = useRef({
    didMount: false,
    previousActive: topBarActionState.isSelectWidgetActive,
    skipNextSync: false,
  });
  const readySessionId =
    bridgeSessionState.status === 'ready' ? bridgeSessionState.sessionId : null;
  const widgetSearchMatches = useMemo(() => {
    if (
      bridgeSessionState.status !== 'ready' ||
      bridgeSessionState.widgetTree.status !== 'loaded'
    ) {
      return [];
    }

    return findWidgetTreeMatches(
      bridgeSessionState.widgetTree.root,
      widgetSearchQuery,
    );
  }, [bridgeSessionState, widgetSearchQuery]);
  const widgetSearchActiveWidgetId =
    widgetSearchActiveIndex >= 0
      ? widgetSearchMatches[widgetSearchActiveIndex]?.nodeId ?? null
      : null;

  useEffect(() => {
    const bootstrap = readSessionBootstrap(window.location.href);
    let isCurrent = true;

    if (bootstrap.status === 'incomplete') {
      return;
    }

    setBridgeSessionState({ status: 'creating' });

    createBridgeSession({
      vmServiceUri: bootstrap.vmServiceUri,
      projectRoot: bootstrap.projectRoot,
    }).then(
      ({ sessionId }) => {
        if (!isCurrent) {
          return;
        }

        setBridgeSessionState({
          status: 'ready',
          sessionId,
          widgetTree: {
            status: 'loading',
          },
        });

        getWidgetTree(sessionId).then(
          ({ root }) => {
            if (!isCurrent) {
              return;
            }

            setBridgeSessionState({
              status: 'ready',
              sessionId,
              widgetTree: {
                status: 'loaded',
                root,
              },
            });
          },
          (error: unknown) => {
            if (!isCurrent) {
              return;
            }

            setBridgeSessionState({
              status: 'ready',
              sessionId,
              widgetTree: {
                status: 'error',
                message:
                  error instanceof Error
                    ? error.message
                    : 'Failed to fetch Flutter Widget Tree',
              },
            });
          },
        );
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

        setBridgeSessionState({
          status: 'error',
          message:
            error instanceof Error
              ? error.message
              : 'Failed to create Ask UI bridge session',
        });
      },
    );

    return () => {
      isCurrent = false;
    };
  }, []);

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

    if (readySessionId === null) {
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

    setSelectWidgetMode(readySessionId, enabled).then(
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
  }, [readySessionId, topBarActionState.isSelectWidgetActive]);

  useEffect(() => {
    if (readySessionId === null) {
      return;
    }

    const subscription = subscribeToBridgeSessionEvents(
      readySessionId,
      syncSelectWidgetModeFromBridgeEvent,
    );

    return () => {
      subscription.close();
    };
  }, [readySessionId]);

  function syncSelectWidgetModeFromBridgeEvent(event: BridgeSessionEvent) {
    if (
      event.sessionId !== readySessionId ||
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
  }

  function handleResizePointerDown(event: PointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    dragStateRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startWidth: widgetTreeWidth,
    };
  }

  function handleResizePointerMove(event: PointerEvent<HTMLDivElement>) {
    const dragState = dragStateRef.current;

    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    const nextWidth = dragState.startWidth + event.clientX - dragState.startX;
    setWidgetTreeWidth(clampPanelWidth(nextWidth));
  }

  function handleResizePointerUp(event: PointerEvent<HTMLDivElement>) {
    if (dragStateRef.current?.pointerId !== event.pointerId) {
      return;
    }

    dragStateRef.current = null;
    event.currentTarget.releasePointerCapture(event.pointerId);
  }

  function handleResizeKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      setWidgetTreeWidth((width) => clampPanelWidth(width - 16));
    }

    if (event.key === 'ArrowRight') {
      event.preventDefault();
      setWidgetTreeWidth((width) => clampPanelWidth(width + 16));
    }

    if (event.key === 'Home') {
      event.preventDefault();
      setWidgetTreeWidth(minWidgetTreeWidth);
    }

    if (event.key === 'End') {
      event.preventDefault();
      setWidgetTreeWidth(maxWidgetTreeWidth);
    }
  }

  async function refreshWidgetTree(sessionId: string): Promise<WidgetTreeLoadState> {
    const { root } = await getWidgetTree(sessionId);

    return {
      status: 'loaded',
      root,
    };
  }

  async function handleSelectWidgetFromTree(widgetId: string) {
    if (bridgeSessionState.status !== 'ready') {
      return;
    }

    const previousWidgetId = selectedWidgetId;
    setSelectedWidgetId(widgetId);
    setWidgetSelectionError(null);

    try {
      await selectWidgetById(bridgeSessionState.sessionId, widgetId);
    } catch (error: unknown) {
      setSelectedWidgetId(previousWidgetId);
      setWidgetSelectionError(
        error instanceof Error ? error.message : 'Failed to select Flutter widget',
      );
    }
  }

  function selectWidgetSearchMatch(nextIndex: number) {
    const match = widgetSearchMatches[nextIndex];

    if (!match) {
      setWidgetSearchActiveIndex(-1);
      return;
    }

    setWidgetSearchActiveIndex(nextIndex);
    void handleSelectWidgetFromTree(match.nodeId);
  }

  function handleWidgetSearchQueryChange(query: string) {
    setWidgetSearchQuery(query);

    if (!query.trim()) {
      setWidgetSearchActiveIndex(-1);
      return;
    }

    const matches =
      bridgeSessionState.status === 'ready' &&
      bridgeSessionState.widgetTree.status === 'loaded'
        ? findWidgetTreeMatches(bridgeSessionState.widgetTree.root, query)
        : [];

    if (matches.length === 0) {
      setWidgetSearchActiveIndex(-1);
      return;
    }

    setWidgetSearchActiveIndex(0);
    void handleSelectWidgetFromTree(matches[0].nodeId);
  }

  function handleWidgetSearchNext() {
    const nextIndex = getNextMatchIndex({
      currentIndex: widgetSearchActiveIndex,
      total: widgetSearchMatches.length,
    });

    selectWidgetSearchMatch(nextIndex);
  }

  function handleWidgetSearchPrevious() {
    const previousIndex = getPreviousMatchIndex({
      currentIndex: widgetSearchActiveIndex,
      total: widgetSearchMatches.length,
    });

    selectWidgetSearchMatch(previousIndex);
  }

  function handleToggleSelectWidget() {
    if (bridgeSessionState.status !== 'ready') {
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
    if (bridgeSessionState.status !== 'ready') {
      setTopBarActionState((state) =>
        markSessionActionUnavailable(state, 'hotReload'),
      );
      return;
    }

    const { sessionId } = bridgeSessionState;
    const previousWidgetTree = bridgeSessionState.widgetTree;

    setTopBarActionState((state) => ({
      ...state,
      hotReload: {
        status: 'running',
      },
    }));
    setSelectedWidgetId(null);
    setWidgetSelectionError(null);
    setWidgetSearchActiveIndex(-1);
    setBridgeSessionState({
      status: 'ready',
      sessionId,
      widgetTree: {
        status: 'loading',
      },
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
      setBridgeSessionState({
        status: 'ready',
        sessionId,
        widgetTree: previousWidgetTree,
      });
      return;
    }

    try {
      const widgetTree = await refreshWidgetTree(sessionId);
      setBridgeSessionState({
        status: 'ready',
        sessionId,
        widgetTree,
      });
      setTopBarActionState((state) => ({
        ...state,
        hotReload: {
          status: 'idle',
          message: 'Hot reload completed.',
        },
      }));
    } catch (error: unknown) {
      setBridgeSessionState({
        status: 'ready',
        sessionId,
        widgetTree: {
          status: 'error',
          message:
            error instanceof Error
              ? error.message
              : 'Failed to fetch Flutter Widget Tree',
        },
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

  async function handleRefreshWidgetTree() {
    if (bridgeSessionState.status !== 'ready') {
      return;
    }

    const { sessionId } = bridgeSessionState;

    setSelectedWidgetId(null);
    setWidgetSelectionError(null);
    setWidgetSearchActiveIndex(-1);
    setBridgeSessionState({
      status: 'ready',
      sessionId,
      widgetTree: {
        status: 'loading',
      },
    });

    try {
      const widgetTree = await refreshWidgetTree(sessionId);
      setBridgeSessionState({
        status: 'ready',
        sessionId,
        widgetTree,
      });
    } catch (error: unknown) {
      setBridgeSessionState({
        status: 'ready',
        sessionId,
        widgetTree: {
          status: 'error',
          message:
            error instanceof Error
              ? error.message
              : 'Failed to fetch Flutter Widget Tree',
        },
      });
    }
  }

  async function handleHotRestart() {
    if (bridgeSessionState.status !== 'ready') {
      setTopBarActionState((state) =>
        markSessionActionUnavailable(state, 'hotRestart'),
      );
      return;
    }

    const { sessionId } = bridgeSessionState;

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

  return (
    <main className="ask-ui-workbench">
      <TopBar
        hotReload={topBarActionState.hotReload}
        hotRestart={topBarActionState.hotRestart}
        isSelectWidgetActive={topBarActionState.isSelectWidgetActive}
        onHotReload={handleHotReload}
        onHotRestart={handleHotRestart}
        onToggleSelectWidget={handleToggleSelectWidget}
        statusMessage={getTopBarStatusMessage(topBarActionState)}
      />
      <div
        className="workbench-content"
        style={{ '--widget-tree-width': `${widgetTreeWidth}px` } as CSSProperties}
      >
        <WidgetTreePanel
          bridgeSessionState={bridgeSessionState}
          canRefresh={
            bridgeSessionState.status === 'ready' &&
            bridgeSessionState.widgetTree.status !== 'loading'
          }
          searchQuery={widgetSearchQuery}
          searchMatches={widgetSearchMatches}
          searchActiveIndex={widgetSearchActiveIndex}
          searchActiveWidgetId={widgetSearchActiveWidgetId}
          selectedWidgetId={selectedWidgetId}
          selectionError={widgetSelectionError}
          onRefresh={handleRefreshWidgetTree}
          onSearchQueryChange={handleWidgetSearchQueryChange}
          onSearchNext={handleWidgetSearchNext}
          onSearchPrevious={handleWidgetSearchPrevious}
          onSelectWidget={handleSelectWidgetFromTree}
        />
        <div
          aria-label="Resize widget tree panel"
          aria-orientation="vertical"
          aria-valuemax={maxWidgetTreeWidth}
          aria-valuemin={minWidgetTreeWidth}
          aria-valuenow={widgetTreeWidth}
          className="panel-resize-handle"
          onKeyDown={handleResizeKeyDown}
          onPointerDown={handleResizePointerDown}
          onPointerMove={handleResizePointerMove}
          onPointerUp={handleResizePointerUp}
          role="separator"
          tabIndex={0}
        />
        <DeviceStage isSelectWidgetActive={topBarActionState.isSelectWidgetActive} />
        <SelectionNotesPanel />
      </div>
    </main>
  );
}
