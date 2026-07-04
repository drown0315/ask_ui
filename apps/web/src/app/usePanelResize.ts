import {
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent,
  type PointerEvent,
} from 'react';

type UsePanelResizeOptions = {
  minWidth: number;
  maxWidth: number;
  defaultWidth: number;
};

type ResizeHandleProps = {
  'aria-label': string;
  'aria-orientation': 'vertical';
  'aria-valuemax': number;
  'aria-valuemin': number;
  'aria-valuenow': number;
  className: string;
  onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => void;
  onPointerDown: (event: PointerEvent<HTMLDivElement>) => void;
  onPointerMove: (event: PointerEvent<HTMLDivElement>) => void;
  onPointerUp: (event: PointerEvent<HTMLDivElement>) => void;
  role: 'separator';
  tabIndex: number;
};

function clampPanelWidth(width: number, minWidth: number, maxWidth: number) {
  return Math.min(maxWidth, Math.max(minWidth, width));
}

/**
 * Manage keyboard and pointer resizing for the Widget Tree side panel.
 *
 * Args:
 * - `options`: Minimum, maximum, and initial panel widths in CSS pixels.
 *
 * Returns:
 * The CSS custom property for the workbench grid and ARIA/event props for the
 * resize handle element.
 *
 * Example:
 * `usePanelResize({minWidth: 260, maxWidth: 520, defaultWidth: 360})` returns a
 * `contentStyle` object whose `--widget-tree-width` value updates while the
 * user drags the resize handle.
 */
export function usePanelResize(options: UsePanelResizeOptions): {
  contentStyle: CSSProperties;
  resizeHandleProps: ResizeHandleProps;
} {
  const { minWidth, maxWidth, defaultWidth } = options;
  const [width, setWidth] = useState(defaultWidth);
  const dragStateRef = useRef<{
    pointerId: number;
    startX: number;
    startWidth: number;
  } | null>(null);

  function setClampedWidth(nextWidth: number) {
    setWidth(clampPanelWidth(nextWidth, minWidth, maxWidth));
  }

  function handlePointerDown(event: PointerEvent<HTMLDivElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    dragStateRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startWidth: width,
    };
  }

  function handlePointerMove(event: PointerEvent<HTMLDivElement>) {
    const dragState = dragStateRef.current;

    if (!dragState || dragState.pointerId !== event.pointerId) {
      return;
    }

    setClampedWidth(dragState.startWidth + event.clientX - dragState.startX);
  }

  function handlePointerUp(event: PointerEvent<HTMLDivElement>) {
    if (dragStateRef.current?.pointerId !== event.pointerId) {
      return;
    }

    dragStateRef.current = null;
    event.currentTarget.releasePointerCapture(event.pointerId);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      setClampedWidth(width - 16);
    }

    if (event.key === 'ArrowRight') {
      event.preventDefault();
      setClampedWidth(width + 16);
    }

    if (event.key === 'Home') {
      event.preventDefault();
      setWidth(minWidth);
    }

    if (event.key === 'End') {
      event.preventDefault();
      setWidth(maxWidth);
    }
  }

  return {
    contentStyle: { '--widget-tree-width': `${width}px` } as CSSProperties,
    resizeHandleProps: {
      'aria-label': 'Resize widget tree panel',
      'aria-orientation': 'vertical',
      'aria-valuemax': maxWidth,
      'aria-valuemin': minWidth,
      'aria-valuenow': width,
      className: 'panel-resize-handle',
      onKeyDown: handleKeyDown,
      onPointerDown: handlePointerDown,
      onPointerMove: handlePointerMove,
      onPointerUp: handlePointerUp,
      role: 'separator',
      tabIndex: 0,
    },
  };
}
