const CHAT_HISTORY_BOTTOM_THRESHOLD_PX = 48;

/**
 * Current scroll measurements for the Chat History scroll container.
 *
 * It contains the browser values needed to decide whether the developer is
 * reviewing older messages or is close enough to the latest message for an
 * automatic scroll.
 *
 * Example:
 * With `scrollHeight=640`, `clientHeight=240`, and `scrollTop=356`, the bottom
 * gap is 44 px, so Chat History is treated as near the latest message.
 */
export type ChatHistoryScrollMetrics = {
  /** Visible height of the Chat History scroll container in pixels. */
  clientHeight: number;

  /** Total scrollable content height of Chat History in pixels. */
  scrollHeight: number;

  /** Current vertical scroll offset from the top of Chat History in pixels. */
  scrollTop: number;
};

/**
 * Return whether Chat History is close enough to the bottom to auto-scroll.
 *
 * Args:
 *   metrics: Browser scroll measurements from the Chat History container.
 *     Negative or overscrolled bottom gaps still count as near the bottom
 *     because the latest message is already visible.
 *
 * Returns:
 *   `true` when the bottom gap is at most 48 px; otherwise `false`.
 *
 * Example:
 *   `scrollHeight=640`, `clientHeight=240`, and `scrollTop=356` returns
 *   `true` because the bottom gap is 44 px.
 */
export function isChatHistoryNearBottom(
  metrics: ChatHistoryScrollMetrics,
): boolean {
  return (
    metrics.scrollHeight - metrics.clientHeight - metrics.scrollTop <=
    CHAT_HISTORY_BOTTOM_THRESHOLD_PX
  );
}

/**
 * Decide how Chat History should react after the rendered message count changes.
 *
 * Args:
 *   isNearBottom: Whether the developer was near the latest message before the
 *     new message count rendered. When `true`, Chat History should keep the
 *     latest message in view.
 *   messageCountChanged: Whether a message was added or removed. When `false`,
 *     the function returns no scroll action and no new-message indicator.
 *
 * Returns:
 *   An object with two UI decisions:
 *   - `shouldScrollToBottom`: scroll the Chat History container to its bottom.
 *   - `showNewMessageIndicator`: show the compact new-message affordance while
 *     the developer remains away from the bottom.
 *
 * Example:
 *   A new agent reply arriving while `isNearBottom=false` returns
 *   `{ shouldScrollToBottom: false, showNewMessageIndicator: true }`.
 */
export function getChatHistoryViewportAfterMessageChange({
  isNearBottom,
  messageCountChanged,
}: {
  isNearBottom: boolean;
  messageCountChanged: boolean;
}): {
  shouldScrollToBottom: boolean;
  showNewMessageIndicator: boolean;
} {
  if (!messageCountChanged) {
    return {
      shouldScrollToBottom: false,
      showNewMessageIndicator: false,
    };
  }

  return {
    shouldScrollToBottom: isNearBottom,
    showNewMessageIndicator: !isNearBottom,
  };
}

/**
 * Decide whether the new-message indicator remains visible after scrolling.
 *
 * Args:
 *   isNearBottom: Whether the current scroll position is near the latest
 *     message after the scroll event.
 *   showNewMessageIndicator: Current indicator visibility before the scroll
 *     event is applied.
 *
 * Returns:
 *   The next indicator visibility. Scrolling near the bottom clears the
 *   indicator; scrolling elsewhere leaves the current value unchanged.
 *
 * Example:
 *   `{ isNearBottom: true, showNewMessageIndicator: true }` returns
 *   `{ showNewMessageIndicator: false }`.
 */
export function getChatHistoryViewportAfterScroll({
  isNearBottom,
  showNewMessageIndicator,
}: {
  isNearBottom: boolean;
  showNewMessageIndicator: boolean;
}): {
  showNewMessageIndicator: boolean;
} {
  return {
    showNewMessageIndicator: isNearBottom ? false : showNewMessageIndicator,
  };
}
