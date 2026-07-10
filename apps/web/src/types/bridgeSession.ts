export type WidgetBounds = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type WidgetTreeNode = {
  id: string;
  label: string;
  bounds?: WidgetBounds;
  sourceLocation?: string;
  visibleText?: string;
  semanticInfo?: string;
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
      missing: Array<
        'vmServiceUri' | 'projectRoot' | 'deviceId' | 'bridgeUrl' | 'sessionId'
      >;
    }
  | {
      status: 'creating';
    }
  | {
      status: 'ready';
      sessionId: string;
      projectRoot: string;
      targetDeviceId?: string;
      targetDeviceDisplayName?: string;
      clientId: string;
      readOnly: boolean;
    }
  | {
      status: 'error';
      message: string;
    };
