import { useEffect, useState } from 'react';
import { createBridgeSession } from '../services/askUiBridgeClient';
import type { BridgeSessionState } from '../types/bridgeSession';
import { readSessionBootstrap } from './sessionBootstrap';

function initialBridgeSessionState(locationHref: string): BridgeSessionState {
  const bootstrap = readSessionBootstrap(locationHref);

  if (bootstrap.status === 'incomplete') {
    return {
      status: 'incomplete',
      missing: bootstrap.missing,
    };
  }

  return {
    status: 'creating',
  };
}

function getBridgeClientId(): string {
  const storageKey = 'ask-ui-bridge-client-id';
  try {
    const existingClientId = window.sessionStorage.getItem(storageKey);
    if (existingClientId) {
      return existingClientId;
    }

    const nextClientId = window.crypto.randomUUID();
    window.sessionStorage.setItem(storageKey, nextClientId);
    return nextClientId;
  } catch {
    return `client-${Math.random().toString(36).slice(2)}`;
  }
}

/**
 * Create or reuse the bridge session described by the workbench URL.
 *
 * Args:
 * - `locationHref`: Full browser URL containing `vmServiceUri`, `projectRoot`,
 *   and `deviceId` query parameters.
 *
 * Returns:
 * The current bridge session state plus the ready session id when creation has
 * succeeded.
 *
 * Example:
 * A URL with all required parameters transitions from `creating` to `ready`
 * after the local bridge returns a `sessionId`.
 */
export function useBridgeSession(locationHref: string): {
  bridgeSessionState: BridgeSessionState;
  readySessionId: string | null;
} {
  const [bridgeSessionState, setBridgeSessionState] =
    useState<BridgeSessionState>(() => initialBridgeSessionState(locationHref));

  useEffect(() => {
    const bootstrap = readSessionBootstrap(locationHref);
    let isCurrent = true;

    if (bootstrap.status === 'incomplete') {
      setBridgeSessionState({
        status: 'incomplete',
        missing: bootstrap.missing,
      });
      return;
    }

    setBridgeSessionState({ status: 'creating' });
    const clientId = getBridgeClientId();

    createBridgeSession({
      vmServiceUri: bootstrap.vmServiceUri,
      projectRoot: bootstrap.projectRoot,
      deviceId: bootstrap.deviceId,
      clientId,
    }).then(
      ({ sessionId, targetDevice, readOnly }) => {
        if (!isCurrent) {
          return;
        }

        setBridgeSessionState({
          status: 'ready',
          sessionId,
          projectRoot: bootstrap.projectRoot,
          targetDeviceId: bootstrap.deviceId,
          targetDeviceDisplayName:
            targetDevice?.displayName?.trim() || undefined,
          clientId,
          readOnly,
        });
      },
      (error: unknown) => {
        if (!isCurrent) {
          return;
        }

        setBridgeSessionState({
          status: 'error',
          message:
            error instanceof Error
              ? error.message
              : 'Failed to create Ask UI bridge session',
        });
      },
    );

    return () => {
      isCurrent = false;
    };
  }, [locationHref]);

  return {
    bridgeSessionState,
    readySessionId:
      bridgeSessionState.status === 'ready' ? bridgeSessionState.sessionId : null,
  };
}
