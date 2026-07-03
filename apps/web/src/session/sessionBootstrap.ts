export type SessionBootstrap =
  | {
      status: 'ready';
      vmServiceUri: string;
      projectRoot: string;
    }
  | {
      status: 'incomplete';
      missing: Array<'vmServiceUri' | 'projectRoot'>;
    };

/**
 * Read bridge bootstrap parameters from a workbench page URL.
 *
 * Args:
 * - `url`: Browser URL for the Ask UI web page. The function reads
 *   `vmServiceUri` and `projectRoot` from its query string and trims both.
 *
 * Returns:
 * A ready result with both required values, or an incomplete result listing the
 * missing parameter names.
 *
 * Example:
 * `/?vmServiceUri=ws://127.0.0.1:12345/ws&projectRoot=/Users/example/app`
 * returns `{status: 'ready', vmServiceUri, projectRoot}`.
 */
export function readSessionBootstrap(url: string): SessionBootstrap {
  const searchParams = new URL(url).searchParams;
  const vmServiceUri = searchParams.get('vmServiceUri')?.trim() ?? '';
  const projectRoot = searchParams.get('projectRoot')?.trim() ?? '';
  const missing: Array<'vmServiceUri' | 'projectRoot'> = [];

  if (!vmServiceUri) {
    missing.push('vmServiceUri');
  }

  if (!projectRoot) {
    missing.push('projectRoot');
  }

  if (missing.length > 0) {
    return {
      status: 'incomplete',
      missing,
    };
  }

  return {
    status: 'ready',
    vmServiceUri,
    projectRoot,
  };
}
