import { useCallback, useMemo, useState } from 'react';
import {
  getInitialSelectionCommentState,
  getLocatableWidgetIds,
  getSelectedWidgetTarget,
  getSelectionCommentAttachmentTokens,
  getSelectionCommentOverlayMarkers,
  type SelectionCommentAttachmentToken,
} from '../selection-comments/selectionCommentState';
import { selectWidgetById } from '../services/askUiBridgeClient';
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
        locatableWidgetIds,
        state: selectionCommentState,
      }),
    [isSelectWidgetActive, locatableWidgetIds, selectionCommentState],
  );

  const handleSelectedWidgetIdChange = useCallback((widgetId: string | null) => {
    setSelectedWidgetId(widgetId);
    setActiveSelectionCommentId(null);
  }, []);

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
