import type { TargetDeviceDisplay } from '../../session/targetDeviceDisplay';
import type { LiveAppSurfaceState } from '../../live-app-surface/liveAppSurfaceState';

export type LiveAppSurfacePhoneStateContent = {
  label: string;
  detail?: string;
  title: string;
  retryable: boolean;
};

export function getLiveAppSurfacePhoneStateContent(
  surfaceState: LiveAppSurfaceState,
  targetDeviceDisplay: TargetDeviceDisplay,
): LiveAppSurfacePhoneStateContent {
  if (surfaceState.status === 'connecting') {
    return {
      label: 'Connecting device',
      detail: `Preparing ${targetDeviceDisplay.topBarLabel} screen stream`,
      title: 'Connecting device',
      retryable: false,
    };
  }

  if (surfaceState.status === 'failed') {
    return {
      label: surfaceState.message,
      detail: targetDeviceDisplay.surfaceLabel,
      title: surfaceState.message,
      retryable: true,
    };
  }

  if (surfaceState.status === 'waitingForVideo') {
    return {
      label: 'Waiting for video',
      detail: `Preparing ${surfaceState.metadata.deviceId} video stream`,
      title: surfaceState.metadata.deviceId,
      retryable: false,
    };
  }

  return {
    label: targetDeviceDisplay.surfaceLabel,
    title: targetDeviceDisplay.title,
    retryable: false,
  };
}
