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
      missing: Array<'vmServiceUri' | 'projectRoot'>;
    }
  | {
      status: 'creating';
    }
  | {
      status: 'ready';
      sessionId: string;
      widgetTree: WidgetTreeLoadState;
    }
  | {
      status: 'error';
      message: string;
    };
