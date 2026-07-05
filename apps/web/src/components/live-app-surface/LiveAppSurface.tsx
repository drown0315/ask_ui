import type { TargetDeviceDisplay } from '../../session/targetDeviceDisplay';
import type { LiveAppSurfaceState } from '../../live-app-surface/liveAppSurfaceState';
import type { DeviceControlMessage } from '../../live-app-surface/deviceControlProtocol';
import type { DeviceVideoFrameRenderer } from '../../live-app-surface/deviceVideoFrameRenderer';
import { DeviceShell } from './DeviceShell';
import {
  getLiveAppSurfacePhoneStateContent,
  type LiveAppSurfacePhoneStateContent,
} from './liveAppSurfaceContent';

type LiveAppSurfaceProps = {
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
  isSelectWidgetActive,
  onDeviceControlMessage,
  onDeviceVideoRendererChange,
  onRetry,
  surfaceState,
  targetDeviceDisplay,
}: LiveAppSurfaceProps) {
  return (
    <section
      className={`workbench-panel live-app-surface ${
        isSelectWidgetActive ? 'live-app-surface-selecting' : ''
      }`}
    >
      {surfaceState.status === 'renderingVideo' ? (
        <DeviceShell
          onDeviceControlMessage={onDeviceControlMessage}
          onDeviceVideoRendererChange={onDeviceVideoRendererChange}
          surfaceState={surfaceState}
        />
      ) : surfaceState.status === 'waitingForVideo' ? (
        <div className="live-app-surface-waiting-stack">
          <div className="live-app-surface-hidden-device-shell" aria-hidden="true">
            <DeviceShell
              onDeviceControlMessage={onDeviceControlMessage}
              onDeviceVideoRendererChange={onDeviceVideoRendererChange}
              surfaceState={surfaceState}
            />
          </div>
          <PhoneStatePlaceholder
            content={getLiveAppSurfacePhoneStateContent(
              surfaceState,
              targetDeviceDisplay,
            )}
            onRetry={onRetry}
          />
        </div>
      ) : (
        <PhoneStatePlaceholder
          content={getLiveAppSurfacePhoneStateContent(
            surfaceState,
            targetDeviceDisplay,
          )}
          onRetry={onRetry}
        />
      )}
    </section>
  );
}

function PhoneStatePlaceholder({
  content,
  onRetry,
}: {
  content: LiveAppSurfacePhoneStateContent;
  onRetry: () => void;
}) {
  return (
    <div className="live-app-phone-state-shell" title={content.title}>
      <div className="live-app-phone-state-hardware">
        <div className="live-app-phone-state-speaker" />
        <div className="live-app-phone-state-screen">
          <div className="live-app-phone-status-bar">
            <span>9:41</span>
            <span>Ask UI</span>
          </div>
          <div className="live-app-phone-skeleton">
            <div className="live-app-phone-skeleton-hero" />
            <div className="live-app-phone-skeleton-line live-app-phone-skeleton-line-wide" />
            <div className="live-app-phone-skeleton-line" />
            <div className="live-app-phone-skeleton-grid">
              <div />
              <div />
              <div />
              <div />
            </div>
          </div>
          <div className="live-app-phone-state-overlay">
            <div className="live-app-phone-spinner" />
            <div className="live-app-phone-state-title">{content.label}</div>
            {content.detail ? (
              <div className="live-app-phone-state-detail">
                {content.detail}
              </div>
            ) : null}
            {content.retryable ? (
              <button
                className="live-app-surface-retry"
                onClick={onRetry}
                type="button"
              >
                Retry
              </button>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}
