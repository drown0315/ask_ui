import {
  useEffect,
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
import { createBridgeSession } from '../services/askUiBridgeClient';
import { readSessionBootstrap } from '../session/sessionBootstrap';
import type { BridgeSessionState } from '../types/bridgeSession';

const minWidgetTreeWidth = 260;
const maxWidgetTreeWidth = 520;
const defaultWidgetTreeWidth = 360;

function clampPanelWidth(width: number) {
  return Math.min(maxWidgetTreeWidth, Math.max(minWidgetTreeWidth, width));
}

export function AskUiWorkbench() {
  const [widgetTreeWidth, setWidgetTreeWidth] = useState(defaultWidgetTreeWidth);
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
    })
      .then(({ sessionId }) => {
        if (!isCurrent) {
          return;
        }

        setBridgeSessionState({
          status: 'ready',
          sessionId,
        });
      })
      .catch((error: unknown) => {
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
      });

    return () => {
      isCurrent = false;
    };
  }, []);

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
        <WidgetTreePanel bridgeSessionState={bridgeSessionState} />
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
