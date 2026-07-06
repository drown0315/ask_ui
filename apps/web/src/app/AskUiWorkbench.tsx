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
import { getSelectedWidgetTarget } from '../selection-comments/selectionCommentState';
import { useWidgetTree } from '../widget-tree/useWidgetTree';
import { useWorkbenchActions } from '../workbench-actions/useWorkbenchActions';
import { usePanelResize } from './usePanelResize';

export function AskUiWorkbench() {
  const [selectedWidgetId, setSelectedWidgetId] = useState<string | null>(null);
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
  const isReadOnly =
    chatSession.status === 'ready' ? chatSession.readOnly : false;
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
  const handleSelectedWidgetIdChange = useCallback((widgetId: string | null) => {
    setSelectedWidgetId(widgetId);
  }, []);

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
          onDeviceControlMessage={liveAppSurface.sendDeviceControlMessage}
          onDeviceVideoRendererChange={liveAppSurface.setDeviceVideoRenderer}
          onRetry={liveAppSurface.retryLiveAppSurface}
          surfaceState={liveAppSurface.surfaceState}
          targetDeviceDisplay={targetDeviceDisplay}
        />
        <ChatPanel
          chatSessionState={chatSession}
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          selectedWidget={selectedWidget}
          sessionId={readySessionId}
          widgetTreeStatus={widgetTree.widgetTreeState.status}
        />
      </div>
    </main>
  );
}
