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
