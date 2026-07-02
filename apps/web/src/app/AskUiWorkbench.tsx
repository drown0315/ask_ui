import { DeviceStage } from '../components/device-stage/DeviceStage';
import { SelectionNotesPanel } from '../components/selection-notes/SelectionNotesPanel';
import { TopBar } from '../components/top-bar/TopBar';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';

export function AskUiWorkbench() {
  return (
    <main className="ask-ui-workbench">
      <TopBar />
      <div className="workbench-content">
        <WidgetTreePanel />
        <DeviceStage />
        <SelectionNotesPanel />
      </div>
    </main>
  );
}
