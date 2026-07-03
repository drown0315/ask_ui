export type WorkbenchActionStatus = 'idle' | 'running' | 'failed' | 'unsupported';

export type WorkbenchActionState = {
  status: WorkbenchActionStatus;
  message?: string;
};

export type TopBarActionState = {
  isSelectWidgetActive: boolean;
  hotReload: WorkbenchActionState;
  hotRestart: WorkbenchActionState;
};

export type SessionActionName = 'hotReload' | 'hotRestart';

export const initialTopBarActionState: TopBarActionState = {
  isSelectWidgetActive: false,
  hotReload: {
    status: 'idle',
  },
  hotRestart: {
    status: 'idle',
  },
};

export function toggleSelectWidgetMode(state: TopBarActionState): TopBarActionState {
  return {
    ...state,
    isSelectWidgetActive: !state.isSelectWidgetActive,
  };
}

export function markSessionActionUnavailable(
  state: TopBarActionState,
  actionName: SessionActionName,
): TopBarActionState {
  return {
    ...state,
    [actionName]: {
      status: 'failed',
      message:
        actionName === 'hotReload'
          ? 'Bridge session required before hot reload.'
          : 'Bridge session required before hot restart.',
    },
  };
}

export function getTopBarStatusMessage(state: TopBarActionState): string {
  if (state.hotReload.status === 'running') {
    return 'Hot reload running';
  }

  if (state.hotRestart.status === 'running') {
    return 'Hot restart running';
  }

  if (state.hotReload.message) {
    return state.hotReload.message;
  }

  if (state.hotRestart.message) {
    return state.hotRestart.message;
  }

  if (state.isSelectWidgetActive) {
    return 'Select Widget mode on';
  }

  return 'Ready';
}
