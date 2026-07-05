import type { BridgeSessionState } from '../types/bridgeSession';

export type TargetDeviceDisplayStatus =
  | 'incomplete'
  | 'creating'
  | 'error'
  | 'ready';

export type TargetDeviceDisplay = {
  topBarLabel: string;
  surfaceLabel: string;
  title: string;
  status: TargetDeviceDisplayStatus;
};

/**
 * Convert bridge session state into Target Device labels used by the workbench.
 *
 * Args:
 * - `state`: Current bridge session state. Incomplete and creating states do
 *   not have a Target Device yet; ready states carry the real Target Device id.
 *
 * Returns:
 * Stable TopBar and Live App Surface labels for the Target Device area.
 *
 * Example:
 * A ready session for `19271FDF6007TY` named `Pixel 6` returns `Pixel 6` for
 * the TopBar and the raw id for the Live App Surface context.
 */
export function getTargetDeviceDisplay(
  state: BridgeSessionState,
): TargetDeviceDisplay {
  if (state.status === 'incomplete') {
    return {
      topBarLabel: 'Device required',
      surfaceLabel: 'Device required',
      title: 'Device required',
      status: 'incomplete',
    };
  }

  if (state.status === 'creating') {
    return {
      topBarLabel: 'Connecting device',
      surfaceLabel: 'Connecting device',
      title: 'Connecting device',
      status: 'creating',
    };
  }

  if (state.status === 'error') {
    return {
      topBarLabel: 'Device unavailable',
      surfaceLabel: 'Device unavailable',
      title: state.message,
      status: 'error',
    };
  }

  const displayName = state.targetDeviceDisplayName?.trim() ?? '';
  if (displayName) {
    return {
      topBarLabel: displayName,
      surfaceLabel: state.targetDeviceId,
      title: `${displayName} (${state.targetDeviceId})`,
      status: 'ready',
    };
  }

  return {
    topBarLabel: `Device ${state.targetDeviceId}`,
    surfaceLabel: state.targetDeviceId,
    title: state.targetDeviceId,
    status: 'ready',
  };
}
