import type { ChatSessionState } from '../chat/chatSessionState';
import type { BridgeSessionState } from '../types/bridgeSession';

export function getWorkbenchReadOnlyState(
  bridgeSessionState: BridgeSessionState,
  chatSessionState: ChatSessionState,
): boolean {
  if (chatSessionState.status === 'ready') {
    return chatSessionState.readOnly;
  }

  return bridgeSessionState.status === 'ready'
    ? bridgeSessionState.readOnly
    : false;
}
