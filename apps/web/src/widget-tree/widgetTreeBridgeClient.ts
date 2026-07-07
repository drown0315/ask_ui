import {
  bridgeOrigin,
  bridgeRequestError,
  parseBridgeJsonResponse,
} from '../services/bridgeHttp.ts';
import type { GetWidgetTreeResponse } from '../services/bridgeTypes.ts';

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
    throw bridgeRequestError(body, 'Failed to fetch Flutter Widget Tree');
  }

  if (!body.root) {
    throw new Error('Widget Tree response did not include root');
  }

  return {
    root: body.root,
  };
}
