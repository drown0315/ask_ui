export const deviceTouchActions = ['down', 'move', 'up', 'cancel'] as const;
export type DeviceTouchAction = (typeof deviceTouchActions)[number];

export const deviceSystemKeys = ['back', 'home', 'recents'] as const;
export type DeviceSystemKey = (typeof deviceSystemKeys)[number];

export type DeviceTouchMessage = {
  type: 'touch';
  action: DeviceTouchAction;
  pointerId: number;
  x: number;
  y: number;
  screenWidth: number;
  screenHeight: number;
};

export type DeviceSystemKeyMessage = {
  type: 'systemKey';
  key: DeviceSystemKey;
};

export type DeviceControlMessage = DeviceTouchMessage | DeviceSystemKeyMessage;

const maxPointerId = 0xffffffff;

export function shouldSendDeviceControlMessage({
  isInputDisabled,
  controlReady,
}: {
  isInputDisabled: boolean;
  controlReady: boolean;
}): boolean {
  return !isInputDisabled && controlReady;
}

/**
 * Build the JSON touch control message sent over the Device WebSocket.
 *
 * The bridge protocol constrains pointer ids to the unsigned 32-bit range.
 * Coordinates are validated by the bridge against the metadata screen size.
 */
export function buildTouchMessage(
  message: Omit<DeviceTouchMessage, 'type'>,
): DeviceTouchMessage {
  if (
    !Number.isInteger(message.pointerId) ||
    message.pointerId < 0 ||
    message.pointerId > maxPointerId
  ) {
    throw new RangeError('pointerId must be an integer from 0 to 4294967295');
  }

  return {
    type: 'touch',
    ...message,
  };
}

export function buildSystemKeyMessage(
  key: DeviceSystemKey,
): DeviceSystemKeyMessage {
  return {
    type: 'systemKey',
    key,
  };
}
