import {
  bridgeOrigin,
  bridgeRequestError,
  parseBridgeJsonResponse,
} from '../services/bridgeHttp.ts';
import type {
  SelectWidgetModeResponse,
  SelectWidgetModeStatusResponse,
  WidgetSelectionResponse,
} from '../services/bridgeTypes.ts';

export async function setSelectWidgetMode(
  sessionId: string,
  enabled: boolean,
): Promise<SelectWidgetModeResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/select-widget-mode`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({ enabled }),
    },
  );

  const body = await parseBridgeJsonResponse<Partial<SelectWidgetModeResponse>>(
    response,
    'Failed to set Select Widget mode',
  );

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to set Select Widget mode');
  }

  if (body.status !== 'ok' || typeof body.enabled !== 'boolean') {
    throw new Error('Select Widget mode response did not include enabled state');
  }

  return body as SelectWidgetModeResponse;
}

export async function getSelectWidgetModeStatus(
  sessionId: string,
): Promise<SelectWidgetModeStatusResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/select-widget-mode`,
  );

  const body = await parseBridgeJsonResponse<
    Partial<SelectWidgetModeStatusResponse>
  >(response, 'Failed to fetch Select Widget mode status');

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to fetch Select Widget mode status');
  }

  if (body.status !== 'ok' || typeof body.known !== 'boolean') {
    throw new Error('Select Widget mode status response did not include known');
  }

  if (body.known && typeof body.enabled !== 'boolean') {
    throw new Error('Known Select Widget mode status did not include enabled');
  }

  return body as SelectWidgetModeStatusResponse;
}

export async function selectWidgetById(
  sessionId: string,
  widgetId: string,
): Promise<WidgetSelectionResponse> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(
      sessionId,
    )}/widget-selection`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({ widgetId }),
    },
  );

  const body = await parseBridgeJsonResponse<Partial<WidgetSelectionResponse>>(
    response,
    'Failed to select Flutter widget',
  );

  if (!response.ok) {
    throw bridgeRequestError(body, 'Failed to select Flutter widget');
  }

  if (body.status !== 'ok' || typeof body.widgetId !== 'string') {
    throw new Error('Widget selection response did not include widgetId');
  }

  return body as WidgetSelectionResponse;
}
