import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  getInitialSelectionCommentState,
  getLocatableWidgetBoundsById,
  getLocatableWidgetIds,
  getSelectedWidgetTarget,
  getSelectionCommentAttachmentTokens,
  getSelectionCommentOverlayMarkers,
  type SelectionCommentAttachmentToken,
} from '../selection-comments/selectionCommentState';
import {
  selectWidgetById,
  subscribeToBridgeSessionEvents,
} from '../services/askUiBridgeClient';
import type { WidgetTreeLoadState } from '../types/bridgeSession';

type UseWorkbenchSelectionCommentsOptions = {
  isSelectWidgetActive: boolean;
  sessionId: string | null;
  widgetTreeState: WidgetTreeLoadState;
};

export function useWorkbenchSelectionComments({
  isSelectWidgetActive,
  sessionId,
  widgetTreeState,
}: UseWorkbenchSelectionCommentsOptions) {
  const [selectedWidgetId, setSelectedWidgetId] = useState<string | null>(null);
  const [activeSelectionCommentId, setActiveSelectionCommentId] = useState<
    string | null
  >(null);
  const [selectionCommentState, setSelectionCommentState] = useState(
    getInitialSelectionCommentState,
  );

  const selectedWidget = useMemo(() => {
    if (widgetTreeState.status !== 'loaded') {
      return null;
    }

    return getSelectedWidgetTarget(widgetTreeState.root, selectedWidgetId);
  }, [selectedWidgetId, widgetTreeState]);

  const locatableWidgetIds = useMemo(() => {
    if (widgetTreeState.status !== 'loaded') {
      return new Set<string>();
    }

    return getLocatableWidgetIds(widgetTreeState.root);
  }, [widgetTreeState]);

  const locatableWidgetBoundsById = useMemo(() => {
    if (widgetTreeState.status !== 'loaded') {
      return new Map();
    }

    return getLocatableWidgetBoundsById(widgetTreeState.root);
  }, [widgetTreeState]);

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
        isSelectWidgetActive,
        locatableWidgetBoundsById,
        state: selectionCommentState,
      }),
    [isSelectWidgetActive, locatableWidgetBoundsById, selectionCommentState],
  );

  const handleSelectedWidgetIdChange = useCallback((widgetId: string | null) => {
    setSelectedWidgetId(widgetId);
    setActiveSelectionCommentId(null);
  }, []);

  useEffect(() => {
    if (sessionId === null) {
      return;
    }

    const subscription = subscribeToBridgeSessionEvents(sessionId, (event) => {
      if (
        event.sessionId !== sessionId ||
        event.type !== 'widget_selection_changed'
      ) {
        return;
      }

      handleSelectedWidgetIdChange(event.payload.widgetId);
    });

    return () => {
      subscription.close();
    };
  }, [handleSelectedWidgetIdChange, sessionId]);

  const handleAttachmentTokenClick = useCallback(
    (token: SelectionCommentAttachmentToken) => {
      setActiveSelectionCommentId(token.id);

      if (!token.isLocatable || sessionId === null) {
        return;
      }

      setSelectedWidgetId(token.widgetId);
      void selectWidgetById(sessionId, token.widgetId).catch(() => undefined);
    },
    [sessionId],
  );

  return {
    activeSelectionCommentId,
    attachmentTokens,
    handleAttachmentTokenClick,
    handleSelectedWidgetIdChange,
    selectedWidget,
    selectedWidgetId,
    selectionCommentState,
    setSelectionCommentState,
    overlayMarkers,
  };
}
