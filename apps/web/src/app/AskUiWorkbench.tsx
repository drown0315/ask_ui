import { LiveAppSurface } from '../components/live-app-surface/LiveAppSurface';
import { SelectionNotesPanel } from '../components/selection-notes/SelectionNotesPanel';
import { TopBar } from '../components/top-bar/TopBar';
import { getTopBarStatusMessage } from '../components/top-bar/topBarActions';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';
import { getTargetDeviceDisplay } from '../session/targetDeviceDisplay';
import { useLiveAppSurface } from '../live-app-surface/useLiveAppSurface';
import { useBridgeSession } from '../session/useBridgeSession';
import { useWidgetTree } from '../widget-tree/useWidgetTree';
import { useWorkbenchActions } from '../workbench-actions/useWorkbenchActions';
import { usePanelResize } from './usePanelResize';

export function AskUiWorkbench() {
  const { bridgeSessionState, readySessionId } = useBridgeSession(
    window.location.href,
  );
  const liveAppSurface = useLiveAppSurface(readySessionId);
  const widgetTree = useWidgetTree(readySessionId);
  const actions = useWorkbenchActions({
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

  return (
    <main className="ask-ui-workbench">
      <TopBar
        hotReload={actions.topBarActionState.hotReload}
        hotRestart={actions.topBarActionState.hotRestart}
        isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
        onHotReload={actions.handleHotReload}
        onHotRestart={actions.handleHotRestart}
        onToggleSelectWidget={actions.handleToggleSelectWidget}
        statusMessage={getTopBarStatusMessage(actions.topBarActionState)}
        targetDeviceDisplay={targetDeviceDisplay}
      />
      <div className="workbench-content" style={panelResize.contentStyle}>
        <WidgetTreePanel
          bridgeSessionState={bridgeSessionState}
          onRefresh={widgetTree.refreshWidgetTree}
          widgetTreeState={widgetTree.widgetTreeState}
        />
        <div {...panelResize.resizeHandleProps} />
        <LiveAppSurface
          isSelectWidgetActive={actions.topBarActionState.isSelectWidgetActive}
          onDeviceControlMessage={liveAppSurface.sendDeviceControlMessage}
          onDeviceVideoRendererChange={liveAppSurface.setDeviceVideoRenderer}
          onRetry={liveAppSurface.retryLiveAppSurface}
          surfaceState={liveAppSurface.surfaceState}
          targetDeviceDisplay={targetDeviceDisplay}
        />
        <SelectionNotesPanel />
      </div>
    </main>
  );
}
