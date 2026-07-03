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
    }
  | {
      status: 'error';
      message: string;
    };
