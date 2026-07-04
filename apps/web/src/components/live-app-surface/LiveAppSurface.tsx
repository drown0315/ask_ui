import type { TargetDeviceDisplay } from '../../session/targetDeviceDisplay';

type LiveAppSurfaceProps = {
  isSelectWidgetActive: boolean;
  targetDeviceDisplay: TargetDeviceDisplay;
};

export function LiveAppSurface({
  isSelectWidgetActive,
  targetDeviceDisplay,
}: LiveAppSurfaceProps) {
  return (
    <section
      className={`workbench-panel live-app-surface ${
        isSelectWidgetActive ? 'live-app-surface-selecting' : ''
      }`}
    >
      <div className="live-app-surface-placeholder" title={targetDeviceDisplay.title}>
        {targetDeviceDisplay.surfaceLabel}
      </div>
    </section>
  );
}
