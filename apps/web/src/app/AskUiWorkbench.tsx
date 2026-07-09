import { LiveAppSurface } from '../components/live-app-surface/LiveAppSurface';
import { ChatPanel } from '../components/chat/ChatPanel';
import { TopBar } from '../components/top-bar/TopBar';
import { getTopBarStatusMessage } from '../components/top-bar/topBarActions';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';
import { useChatSession } from '../chat/useChatSession';
import { getTargetDeviceDisplay } from '../session/targetDeviceDisplay';
import { useLiveAppSurface } from '../live-app-surface/useLiveAppSurface';
import { useBridgeSession } from '../session/useBridgeSession';
import { useWidgetTree } from '../widget-tree/useWidgetTree';
import { useWorkbenchActions } from '../workbench-actions/useWorkbenchActions';
import { usePanelResize } from './usePanelResize';
import { useWorkbenchSelectionComments } from './useWorkbenchSelectionComments';
import { getWorkbenchReadOnlyState } from './workbenchReadOnlyState';
import './AskUiWorkbench.css';

export function AskUiWorkbench() {
  const { bridgeSessionState, readySessionId } = useBridgeSession(
    window.location.href,
  );
  const liveAppSurface = useLiveAppSurface(readySessionId);
  const clientId =
    bridgeSessionState.status === 'ready' ? bridgeSessionState.clientId : null;
  const projectRoot =
    bridgeSessionState.status === 'ready' ? bridgeSessionState.projectRoot : null;
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
  const selectionComments = useWorkbenchSelectionComments({
    isSelectWidgetActive: actions.topBarActionState.isSelectWidgetActive,
    sessionId: readySessionId,
    widgetTreeState: widgetTree.widgetTreeState,
  });
  const targetDeviceDisplay = getTargetDeviceDisplay(bridgeSessionState);

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
          onSelectedWidgetIdChange={
            selectionComments.handleSelectedWidgetIdChange
          }
          selectedWidgetId={selectionComments.selectedWidgetId}
          widgetTreeState={widgetTree.widgetTreeState}
        />
        <div {...panelResize.resizeHandleProps} />
        <LiveAppSurface
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          isInputDisabled={isReadOnly}
          overlayMarkers={selectionComments.overlayMarkers}
          onDeviceControlMessage={liveAppSurface.sendDeviceControlMessage}
          onDeviceVideoRendererChange={liveAppSurface.setDeviceVideoRenderer}
          onRetry={liveAppSurface.retryLiveAppSurface}
          surfaceState={liveAppSurface.surfaceState}
          targetDeviceDisplay={targetDeviceDisplay}
        />
        <ChatPanel
          activeSelectionCommentId={selectionComments.activeSelectionCommentId}
          attachmentTokens={selectionComments.attachmentTokens}
          chatSessionState={chatSession}
          isReadOnly={isReadOnly}
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          onAttachmentTokenClick={selectionComments.handleAttachmentTokenClick}
          onSelectionCommentStateChange={
            selectionComments.setSelectionCommentState
          }
          selectedWidget={selectionComments.selectedWidget}
          selectionCommentState={selectionComments.selectionCommentState}
          sessionId={readySessionId}
          projectRoot={projectRoot}
          widgetTreeStatus={widgetTree.widgetTreeState.status}
        />
      </div>
    </main>
  );
}
