export type SessionBootstrap =
  | {
      mode: 'create';
      status: 'ready';
      vmServiceUri: string;
      projectRoot: string;
      deviceId: string;
    }
  | {
      mode: 'attach';
      status: 'ready';
      bridgeUrl: string;
      sessionId: string;
      projectRoot?: string;
      deviceId?: string;
    }
  | {
      mode: 'create';
      status: 'incomplete';
      missing: Array<'vmServiceUri' | 'projectRoot' | 'deviceId'>;
    }
  | {
      mode: 'attach';
      status: 'incomplete';
      missing: Array<'bridgeUrl' | 'sessionId'>;
    };

/**
 * Read bridge bootstrap parameters from a workbench page URL.
 *
 * Args:
 * - `url`: Browser URL for the Ask UI web page. The function reads
 *   `vmServiceUri`, `projectRoot`, and `deviceId` from its query string and
 *   trims each value.
 *
 * Returns:
 * A ready result with all required values, or an incomplete result listing the
 * missing parameter names.
 *
 * Example:
 * `/?vmServiceUri=ws://127.0.0.1:12345/ws&projectRoot=/Users/example/app&deviceId=19271FDF6007TY`
 * returns `{status: 'ready', vmServiceUri, projectRoot, deviceId}`.
 */
export function readSessionBootstrap(url: string): SessionBootstrap {
  const searchParams = new URL(url).searchParams;
  const bridgeUrl = searchParams.get('bridgeUrl')?.trim() ?? '';
  const sessionId = searchParams.get('sessionId')?.trim() ?? '';

  if (bridgeUrl || sessionId) {
    const missing: Array<'bridgeUrl' | 'sessionId'> = [];

    if (!bridgeUrl) {
      missing.push('bridgeUrl');
    }

    if (!sessionId) {
      missing.push('sessionId');
    }

    if (missing.length > 0) {
      return {
        mode: 'attach',
        status: 'incomplete',
        missing,
      };
    }

    const deviceId = searchParams.get('deviceId')?.trim() || undefined;
    const projectRoot = searchParams.get('projectRoot')?.trim() || undefined;

    return {
      mode: 'attach',
      status: 'ready',
      bridgeUrl: bridgeUrl.replace(/\/+$/, ''),
      sessionId,
      ...(deviceId ? { deviceId } : {}),
      ...(projectRoot ? { projectRoot } : {}),
    };
  }

  const vmServiceUri = searchParams.get('vmServiceUri')?.trim() ?? '';
  const projectRoot = searchParams.get('projectRoot')?.trim() ?? '';
  const deviceId = searchParams.get('deviceId')?.trim() ?? '';
  const missing: Array<'vmServiceUri' | 'projectRoot' | 'deviceId'> = [];

  if (!vmServiceUri) {
    missing.push('vmServiceUri');
  }

  if (!projectRoot) {
    missing.push('projectRoot');
  }

  if (!deviceId) {
    missing.push('deviceId');
  }

  if (missing.length > 0) {
    return {
      mode: 'create',
      status: 'incomplete',
      missing,
    };
  }

  return {
    mode: 'create',
    status: 'ready',
    vmServiceUri,
    projectRoot,
    deviceId,
  };
}
