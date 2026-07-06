export type WidgetTreeNode = {
  id: string;
  label: string;
  children: WidgetTreeNode[];
};

export type WidgetTreeLoadState =
  | {
      status: 'loading';
    }
  | {
      status: 'loaded';
      root: WidgetTreeNode;
    }
  | {
      status: 'error';
      message: string;
    };

export type BridgeSessionState =
  | {
      status: 'incomplete';
      missing: Array<'vmServiceUri' | 'projectRoot' | 'deviceId'>;
    }
  | {
      status: 'creating';
    }
  | {
      status: 'ready';
      sessionId: string;
      targetDeviceId: string;
      targetDeviceDisplayName?: string;
      clientId: string;
      readOnly: boolean;
    }
  | {
      status: 'error';
      message: string;
    };
