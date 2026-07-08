import {
  bridgeOrigin,
  bridgeRequestError,
  parseBridgeJsonResponse,
} from '../services/bridgeHttp.ts';
import type {
  GetChatSessionResponse,
  SendChatMessageRequest,
  SendPlainTextChatMessageResponse,
} from '../services/bridgeTypes.ts';
import { isAgentStatusResponse } from '../services/bridgeTypes.ts';

export async function getChatSession(
  sessionId: string,
  clientId: string | null = null,
): Promise<GetChatSessionResponse> {
  const url = new URL(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/chat`,
  );
  if (clientId) {
    url.searchParams.set('clientId', clientId);
  }

  const response = await fetch(url.toString());
  const body = await parseBridgeJsonResponse<Partial<GetChatSessionResponse>>(
    response,
    'Failed to load Chat History',
  );

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to load Chat History');
  }

  if (
    body.status !== 'ok' ||
    !isAgentStatusResponse(body.agentStatus) ||
    !Array.isArray(body.messages)
  ) {
    throw new Error('Chat response did not include Chat History');
  }

  return {
    status: 'ok',
    agentStatus: body.agentStatus,
    readOnly: body.readOnly === true,
    messages: body.messages,
  };
}

export async function sendPlainTextChatMessage(
  sessionId: string,
  text: string,
): Promise<SendPlainTextChatMessageResponse> {
  return sendChatMessage(sessionId, { text });
}

export async function sendChatMessage(
  sessionId: string,
  request: SendChatMessageRequest | { text: string },
): Promise<SendPlainTextChatMessageResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/chat/messages`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify(request),
    },
  );

  const body = await parseBridgeJsonResponse<
    Partial<SendPlainTextChatMessageResponse>
  >(response, 'Failed to send Chat message');

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to send Chat message');
  }

  if (body.status !== 'ok' || !body.message) {
    throw new Error('Chat send response did not include the sent message');
  }

  return {
    status: 'ok',
    message: body.message,
  };
}
