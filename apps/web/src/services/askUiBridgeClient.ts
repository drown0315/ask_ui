export type CreateBridgeSessionRequest = {
  vmServiceUri: string;
  projectRoot: string;
};

export type CreateBridgeSessionResponse = {
  sessionId: string;
};

export type WidgetTreeNodeResponse = {
  id: string;
  label: string;
  children: WidgetTreeNodeResponse[];
};

export type GetWidgetTreeResponse = {
  root: WidgetTreeNodeResponse;
};

const defaultBridgeOrigin = 'http://127.0.0.1:8787';

export function resolveBridgeOrigin(envOrigin: string | undefined): string {
  const trimmedOrigin = envOrigin?.trim().replace(/\/+$/, '');

  if (!trimmedOrigin) {
    return defaultBridgeOrigin;
  }

  return trimmedOrigin;
}

export async function parseBridgeJsonResponse<T>(
  response: Response,
  fallbackMessage: string,
): Promise<T & { error?: string; message?: string }> {
  const text = await response.text();

  if (!text.trim()) {
    throw new Error(`${fallbackMessage}: empty response`);
  }

  try {
    return JSON.parse(text) as T & { error?: string };
  } catch {
    throw new Error(`${fallbackMessage}: non-JSON response`);
  }
}

const bridgeOrigin = resolveBridgeOrigin(import.meta.env?.VITE_ASK_UI_BRIDGE_ORIGIN);

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

  const body = await parseBridgeJsonResponse<Partial<CreateBridgeSessionResponse>>(
    response,
    'Failed to create Ask UI bridge session',
  );

  if (!response.ok) {
    throw new Error(
      body.message ?? body.error ?? 'Failed to create Ask UI bridge session',
    );
  }

  if (!body.sessionId) {
    throw new Error('Bridge session response did not include sessionId');
  }

  return {
    sessionId: body.sessionId,
  };
}

export async function getWidgetTree(
  sessionId: string,
): Promise<GetWidgetTreeResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/widget-tree`,
  );

  const body = await parseBridgeJsonResponse<Partial<GetWidgetTreeResponse>>(
    response,
    'Failed to fetch Flutter Widget Tree',
  );

  if (!response.ok) {
    throw new Error(
      body.message ?? body.error ?? 'Failed to fetch Flutter Widget Tree',
    );
  }

  if (!body.root) {
    throw new Error('Widget Tree response did not include root');
  }

  return {
    root: body.root,
  };
}
