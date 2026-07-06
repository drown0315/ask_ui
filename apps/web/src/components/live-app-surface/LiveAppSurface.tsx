import type { TargetDeviceDisplay } from '../../session/targetDeviceDisplay';
import type { LiveAppSurfaceState } from '../../live-app-surface/liveAppSurfaceState';
import type { DeviceControlMessage } from '../../live-app-surface/deviceControlProtocol';
import type { DeviceVideoFrameRenderer } from '../../live-app-surface/deviceVideoFrameRenderer';
import { DeviceShell } from './DeviceShell';

type LiveAppSurfaceProps = {
  isInputDisabled: boolean;
  isSelectWidgetActive: boolean;
  onDeviceControlMessage: (message: DeviceControlMessage) => void;
  onDeviceVideoRendererChange: (
    renderer: DeviceVideoFrameRenderer | null,
  ) => void;
  onRetry: () => void;
  surfaceState: LiveAppSurfaceState;
  targetDeviceDisplay: TargetDeviceDisplay;
};

export function LiveAppSurface({
  isInputDisabled,
  isSelectWidgetActive,
  onDeviceControlMessage,
  onDeviceVideoRendererChange,
  onRetry,
  surfaceState,
  targetDeviceDisplay,
}: LiveAppSurfaceProps) {
  const content = getLiveAppSurfaceContent(surfaceState, targetDeviceDisplay);

  return (
    <section
      className={`workbench-panel live-app-surface ${
        isSelectWidgetActive ? 'live-app-surface-selecting' : ''
      }`}
    >
      {surfaceState.status === 'waitingForVideo' ||
      surfaceState.status === 'renderingVideo' ? (
        <DeviceShell
          isInputDisabled={isInputDisabled}
          onDeviceControlMessage={onDeviceControlMessage}
          onDeviceVideoRendererChange={onDeviceVideoRendererChange}
          surfaceState={surfaceState}
        />
      ) : (
        <div className="live-app-surface-placeholder" title={content.title}>
          <div>{content.label}</div>
          {content.detail ? (
            <div className="live-app-surface-detail">{content.detail}</div>
          ) : null}
          {surfaceState.status === 'failed' ? (
            <button
              className="live-app-surface-retry"
              onClick={onRetry}
              type="button"
            >
              Retry
            </button>
          ) : null}
        </div>
      )}
    </section>
  );
}

function getLiveAppSurfaceContent(
  surfaceState: LiveAppSurfaceState,
  targetDeviceDisplay: TargetDeviceDisplay,
): {
  label: string;
  detail?: string;
  title: string;
} {
  if (surfaceState.status === 'connecting') {
    return {
      label: 'Connecting device',
      title: 'Connecting device',
    };
  }

  if (surfaceState.status === 'waitingForVideo') {
    return {
      label: 'Waiting for video',
      detail: surfaceState.metadata.deviceId,
      title: surfaceState.metadata.deviceId,
    };
  }

  if (surfaceState.status === 'renderingVideo') {
    return {
      label: 'Device video',
      detail: surfaceState.metadata.deviceId,
      title: surfaceState.metadata.deviceId,
    };
  }

  if (surfaceState.status === 'failed') {
    return {
      label: surfaceState.message,
      title: surfaceState.message,
    };
  }

  return {
    label: targetDeviceDisplay.surfaceLabel,
    title: targetDeviceDisplay.title,
  };
}
