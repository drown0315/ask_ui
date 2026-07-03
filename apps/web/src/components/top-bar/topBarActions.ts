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
