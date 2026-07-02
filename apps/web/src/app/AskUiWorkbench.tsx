import {
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type PointerEvent,
} from 'react';
import { DeviceStage } from '../components/device-stage/DeviceStage';
import { SelectionNotesPanel } from '../components/selection-notes/SelectionNotesPanel';
import { TopBar } from '../components/top-bar/TopBar';
import { WidgetTreePanel } from '../components/widget-tree/WidgetTreePanel';

const minWidgetTreeWidth = 260;
const maxWidgetTreeWidth = 520;
const defaultWidgetTreeWidth = 360;

function clampPanelWidth(width: number) {
  return Math.min(maxWidgetTreeWidth, Math.max(minWidgetTreeWidth, width));
}

export function AskUiWorkbench() {
  const [widgetTreeWidth, setWidgetTreeWidth] = useState(defaultWidgetTreeWidth);
  const dragStateRef = useRef<{
    pointerId: number;
    startX: number;
    startWidth: number;
  } | null>(null);

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

  return (
    <main className="ask-ui-workbench">
      <TopBar />
      <div
        className="workbench-content"
        style={{ '--widget-tree-width': `${widgetTreeWidth}px` } as CSSProperties}
      >
        <WidgetTreePanel />
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
        <DeviceStage />
        <SelectionNotesPanel />
      </div>
    </main>
  );
}
