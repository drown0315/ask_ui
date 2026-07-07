import { bridgeOrigin, parseBridgeJsonResponse } from '../services/bridgeHttp.ts';
import type { SelectionCommentSnapshotCaptureResult } from '../services/bridgeTypes.ts';

export async function captureSelectionCommentSnapshot(
  sessionId: string,
  commentId: string,
): Promise<SelectionCommentSnapshotCaptureResult> {
  const response = await fetch(
    `${bridgeOrigin}/api/sessions/${encodeURIComponent(sessionId)}/snapshots`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        commentId,
        format: 'png',
        maxSizeBytes: 1_258_291,
        scope: 'full_device',
      }),
    },
  );

  const body = await parseBridgeJsonResponse<{
    status?: 'ok' | 'unavailable';
    snapshot?: {
      path?: unknown;
      mimeType?: unknown;
      sizeBytes?: unknown;
    };
  }>(response, 'Failed to capture Selection Comment snapshot');

  if (!response.ok || body.status === 'unavailable') {
    return {
      status: 'unavailable',
    };
  }

  if (
    body.status === 'ok' &&
    body.snapshot?.mimeType === 'image/png' &&
    typeof body.snapshot.path === 'string' &&
    typeof body.snapshot.sizeBytes === 'number'
  ) {
    return {
      status: 'available',
      path: body.snapshot.path,
      mimeType: body.snapshot.mimeType,
      sizeBytes: body.snapshot.sizeBytes,
    };
  }

  return {
    status: 'unavailable',
  };
}
