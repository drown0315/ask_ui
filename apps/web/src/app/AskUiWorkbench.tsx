import { useCallback, useMemo, useState } from 'react';
import { LiveAppSurface } from '../components/live-app-surface/LiveAppSurface';
import { ChatPanel } from '../components/chat/ChatPanel';
import { TopBar } from '../components/top-bar/TopBar';
import { getTopBarStatusMessage } from '../components/top-bar/topBarActions';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';
import { useChatSession } from '../chat/useChatSession';
import { getTargetDeviceDisplay } from '../session/targetDeviceDisplay';
import { useLiveAppSurface } from '../live-app-surface/useLiveAppSurface';
import { useBridgeSession } from '../session/useBridgeSession';
import {
  getInitialSelectionCommentState,
  getLocatableWidgetIds,
  getSelectedWidgetTarget,
  getSelectionCommentAttachmentTokens,
  getSelectionCommentOverlayMarkers,
  type SelectionCommentAttachmentToken,
} from '../selection-comments/selectionCommentState';
import { selectWidgetById } from '../services/askUiBridgeClient';
import { useWidgetTree } from '../widget-tree/useWidgetTree';
import { useWorkbenchActions } from '../workbench-actions/useWorkbenchActions';
import { usePanelResize } from './usePanelResize';
import { getWorkbenchReadOnlyState } from './workbenchReadOnlyState';

export function AskUiWorkbench() {
  const [selectedWidgetId, setSelectedWidgetId] = useState<string | null>(null);
  const [activeSelectionCommentId, setActiveSelectionCommentId] = useState<
    string | null
  >(null);
  const [selectionCommentState, setSelectionCommentState] = useState(
    getInitialSelectionCommentState,
  );
  const { bridgeSessionState, readySessionId } = useBridgeSession(
    window.location.href,
  );
  const liveAppSurface = useLiveAppSurface(readySessionId);
  const clientId =
    bridgeSessionState.status === 'ready' ? bridgeSessionState.clientId : null;
  const chatSession = useChatSession({
    clientId,
    sessionId: readySessionId,
  });
  const isReadOnly = getWorkbenchReadOnlyState(bridgeSessionState, chatSession);
  const widgetTree = useWidgetTree(readySessionId);
  const actions = useWorkbenchActions({
    isReadOnly,
    sessionId: readySessionId,
    widgetTreeState: widgetTree.widgetTreeState,
    setWidgetTreeState: widgetTree.setWidgetTreeState,
    refreshWidgetTree: widgetTree.refreshWidgetTree,
  });
  const panelResize = usePanelResize({
    minWidth: 260,
    maxWidth: 520,
    defaultWidth: 360,
  });
  const targetDeviceDisplay = getTargetDeviceDisplay(bridgeSessionState);
  const selectedWidget = useMemo(() => {
    if (widgetTree.widgetTreeState.status !== 'loaded') {
      return null;
    }

    return getSelectedWidgetTarget(widgetTree.widgetTreeState.root, selectedWidgetId);
  }, [selectedWidgetId, widgetTree.widgetTreeState]);
  const locatableWidgetIds = useMemo(() => {
    if (widgetTree.widgetTreeState.status !== 'loaded') {
      return new Set<string>();
    }

    return getLocatableWidgetIds(widgetTree.widgetTreeState.root);
  }, [widgetTree.widgetTreeState]);
  const attachmentTokens = useMemo(
    () =>
      getSelectionCommentAttachmentTokens(
        selectionCommentState,
        locatableWidgetIds,
      ),
    [locatableWidgetIds, selectionCommentState],
  );
  const overlayMarkers = useMemo(
    () =>
      getSelectionCommentOverlayMarkers({
        isSelectWidgetActive: actions.topBarActionState.isSelectWidgetActive,
        locatableWidgetIds,
        state: selectionCommentState,
      }),
    [
      actions.topBarActionState.isSelectWidgetActive,
      locatableWidgetIds,
      selectionCommentState,
    ],
  );
  const handleSelectedWidgetIdChange = useCallback((widgetId: string | null) => {
    setSelectedWidgetId(widgetId);
    setActiveSelectionCommentId(null);
  }, []);
  const handleAttachmentTokenClick = useCallback(
    (token: SelectionCommentAttachmentToken) => {
      setActiveSelectionCommentId(token.id);

      if (!token.isLocatable || readySessionId === null) {
        return;
      }

      setSelectedWidgetId(token.widgetId);
      void selectWidgetById(readySessionId, token.widgetId).catch(() => undefined);
    },
    [readySessionId],
  );

  return (
    <main className="ask-ui-workbench">
      <TopBar
        hotReload={actions.topBarActionState.hotReload}
        hotRestart={actions.topBarActionState.hotRestart}
        isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
        onHotReload={actions.handleHotReload}
        onHotRestart={actions.handleHotRestart}
        onToggleSelectWidget={actions.handleToggleSelectWidget}
        statusMessage={getTopBarStatusMessage(
          actions.topBarActionState,
          targetDeviceDisplay,
        )}
        targetDeviceDisplay={targetDeviceDisplay}
      />
      <div className="workbench-content" style={panelResize.contentStyle}>
        <WidgetTreePanel
          bridgeSessionState={bridgeSessionState}
          onRefresh={widgetTree.refreshWidgetTree}
          onSelectedWidgetIdChange={handleSelectedWidgetIdChange}
          selectedWidgetId={selectedWidgetId}
          widgetTreeState={widgetTree.widgetTreeState}
        />
        <div {...panelResize.resizeHandleProps} />
        <LiveAppSurface
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          isInputDisabled={isReadOnly}
          overlayMarkers={overlayMarkers}
          onDeviceControlMessage={liveAppSurface.sendDeviceControlMessage}
          onDeviceVideoRendererChange={liveAppSurface.setDeviceVideoRenderer}
          onRetry={liveAppSurface.retryLiveAppSurface}
          surfaceState={liveAppSurface.surfaceState}
          targetDeviceDisplay={targetDeviceDisplay}
        />
        <ChatPanel
          activeSelectionCommentId={activeSelectionCommentId}
          attachmentTokens={attachmentTokens}
          chatSessionState={chatSession}
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          onAttachmentTokenClick={handleAttachmentTokenClick}
          onSelectionCommentStateChange={setSelectionCommentState}
          selectedWidget={selectedWidget}
          selectionCommentState={selectionCommentState}
          sessionId={readySessionId}
          widgetTreeStatus={widgetTree.widgetTreeState.status}
        />
      </div>
    </main>
  );
}
