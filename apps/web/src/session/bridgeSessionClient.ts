import { bridgeOrigin, bridgeRequestError, parseBridgeJsonResponse } from '../services/bridgeHttp.ts';
import type {
  CreateBridgeSessionRequest,
  CreateBridgeSessionResponse,
} from '../services/bridgeTypes.ts';

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

  const body = await parseBridgeJsonResponse<
    Partial<CreateBridgeSessionResponse>
  >(response, 'Failed to create Ask UI bridge session');

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to create Ask UI bridge session');
  }

  if (!body.sessionId) {
    throw new Error('Bridge session response did not include sessionId');
  }

  const responseBody: CreateBridgeSessionResponse = {
    sessionId: body.sessionId,
    readOnly: body.readOnly === true,
  };

  if (
    body.targetDevice &&
    typeof body.targetDevice === 'object' &&
    'id' in body.targetDevice &&
    typeof body.targetDevice.id === 'string'
  ) {
    responseBody.targetDevice = {
      id: body.targetDevice.id,
      displayName:
        'displayName' in body.targetDevice &&
        typeof body.targetDevice.displayName === 'string'
          ? body.targetDevice.displayName
          : undefined,
    };
  }

  return responseBody;
}
