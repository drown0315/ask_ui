type DeviceStageProps = {
  isSelectWidgetActive: boolean;
};

export function DeviceStage({ isSelectWidgetActive }: DeviceStageProps) {
  return (
    <section
      className={`workbench-panel device-stage ${
        isSelectWidgetActive ? 'device-stage-selecting' : ''
      }`}
    >
      <div className="device-stage-placeholder">
        {isSelectWidgetActive ? 'Select Widget Mode' : 'Device Stage'}
      </div>
    </section>
  );
}
