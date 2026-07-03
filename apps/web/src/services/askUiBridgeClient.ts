export type CreateBridgeSessionRequest = {
  vmServiceUri: string;
  projectRoot: string;
};

export type CreateBridgeSessionResponse = {
  sessionId: string;
};

const bridgeOrigin = import.meta.env.VITE_ASK_UI_BRIDGE_ORIGIN ?? '';

export async function createBridgeSession(
  request: CreateBridgeSessionRequest,
): Promise<CreateBridgeSessionResponse> {
  const response = await fetch(`${bridgeOrigin}/api/sessions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
    },
    body: JSON.stringify(request),
  });

  const body = (await response.json()) as Partial<CreateBridgeSessionResponse> & {
    error?: string;
  };

  if (!response.ok) {
    throw new Error(body.error ?? 'Failed to create Ask UI bridge session');
  }

  if (!body.sessionId) {
    throw new Error('Bridge session response did not include sessionId');
  }

  return {
    sessionId: body.sessionId,
  };
}
