const defaultBridgeOrigin = 'http://127.0.0.1:8787';

export class BridgeRequestError extends Error {
  readonly code?: string;

  constructor(message: string, code?: string) {
    super(message);
    this.name = 'BridgeRequestError';
    this.code = code;
  }
}

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

export let bridgeOrigin = resolveBridgeOrigin(
  import.meta.env?.VITE_ASK_UI_BRIDGE_ORIGIN,
);

export function setBridgeOriginOverride(origin: string): void {
  bridgeOrigin = resolveBridgeOrigin(origin);
}

export function resetBridgeOriginOverride(): void {
  bridgeOrigin = resolveBridgeOrigin(import.meta.env?.VITE_ASK_UI_BRIDGE_ORIGIN);
}

export function bridgeRequestError(
  body: { error?: string; message?: string },
  fallbackMessage: string,
): BridgeRequestError {
  return new BridgeRequestError(
    body.message ?? body.error ?? fallbackMessage,
    body.error,
  );
}
