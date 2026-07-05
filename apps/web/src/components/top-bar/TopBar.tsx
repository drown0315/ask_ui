import type { WorkbenchActionState } from './topBarActions';
import type { TargetDeviceDisplay } from '../../session/targetDeviceDisplay';

type TopBarProps = {
  isSelectWidgetActive: boolean;
  hotReload: WorkbenchActionState;
  hotRestart: WorkbenchActionState;
  targetDeviceDisplay: TargetDeviceDisplay;
  statusMessage: string;
  onToggleSelectWidget: () => void;
  onHotReload: () => void;
  onHotRestart: () => void;
};

function getActionLabel(label: string, action: WorkbenchActionState) {
  if (action.status === 'running') {
    return `${label}...`;
  }

  return label;
}

export function TopBar({
  isSelectWidgetActive,
  hotReload,
  hotRestart,
  targetDeviceDisplay,
  statusMessage,
  onToggleSelectWidget,
  onHotReload,
  onHotRestart,
}: TopBarProps) {
  return (
    <header className="top-bar">
      <div className="top-bar-brand">
        <div className="brand-mark" aria-hidden="true" />
        <span>Ask UI</span>
      </div>

      <div className="top-bar-session" aria-label="Target device status">
        <span className="status-dot" aria-hidden="true" />
        <span className="target-device-label" title={targetDeviceDisplay.title}>
          {targetDeviceDisplay.topBarLabel}
        </span>
        <span className="session-muted" title={statusMessage}>
          {statusMessage}
        </span>
      </div>

      <div className="top-bar-actions" aria-label="Workbench actions">
        <button
          aria-pressed={isSelectWidgetActive}
          className={`toolbar-button ${
            isSelectWidgetActive ? 'toolbar-button-active' : ''
          }`}
          onClick={onToggleSelectWidget}
          type="button"
        >
          Select Widget
        </button>
        <button
          className={`toolbar-button ${
            hotReload.status === 'failed' ? 'toolbar-button-error' : ''
          }`}
          disabled={hotReload.status === 'running'}
          onClick={onHotReload}
          title={hotReload.message}
          type="button"
        >
          {getActionLabel('Hot Reload', hotReload)}
        </button>
        <button
          className="toolbar-button"
          disabled={hotRestart.status === 'running'}
          onClick={onHotRestart}
          title={hotRestart.message}
          type="button"
        >
          {getActionLabel('Hot Restart', hotRestart)}
        </button>
      </div>
    </header>
  );
}
