export type CreateBridgeSessionRequest = {
  vmServiceUri: string;
  projectRoot: string;
  deviceId: string;
  clientId?: string;
};

export type CreateBridgeSessionResponse = {
  sessionId: string;
  targetDevice?: {
    id: string;
    displayName?: string;
  };
  readOnly: boolean;
};

export type WidgetTreeNodeResponse = {
  id: string;
  label: string;
  sourceLocation?: string;
  visibleText?: string;
  semanticInfo?: string;
  children: WidgetTreeNodeResponse[];
};

export type GetWidgetTreeResponse = {
  root: WidgetTreeNodeResponse;
};

export type HotReloadSessionResponse = {
  status: 'ok';
  message?: string;
  reloadReport?: Record<string, unknown>;
};

export type HotRestartSessionResponse = {
  status: 'ok';
  message?: string;
};

export type SelectWidgetModeResponse = {
  status: 'ok';
  enabled: boolean;
  message?: string;
};

export type SelectWidgetModeStatusResponse = {
  status: 'ok';
  known: boolean;
  enabled?: boolean;
};

export type WidgetSelectionResponse = {
  status: 'ok';
  widgetId: string;
  message?: string;
};

export type AgentStatusResponse =
  | 'waiting_for_agent'
  | 'agent_ready'
  | 'agent_working';

export type ChatMessageResponse = {
  id: string;
  role: 'user' | 'agent' | 'system';
  text: string;
};

export type GetChatSessionResponse = {
  status: 'ok';
  agentStatus: AgentStatusResponse;
  readOnly: boolean;
  messages: ChatMessageResponse[];
};

export type SendPlainTextChatMessageResponse = {
  status: 'ok';
  message: ChatMessageResponse;
};

export type ChatMessageSelectionCommentAttachment = {
  id: string;
  commentText: string;
  selectedWidget: {
    id: string;
    displayLabel: string;
    sourceLocation?: string;
    visibleText?: string;
    semanticInfo?: string;
  };
  snapshot:
    | {
        status: 'available';
        path: string;
      }
    | {
        status: 'unavailable';
      };
};

export type ChatMessageRequestPart =
  | {
      type: 'selection_comment';
      attachment: ChatMessageSelectionCommentAttachment;
    }
  | {
      type: 'text';
      text: string;
    };

export type SendChatMessageRequest = {
  context: {
    projectRoot: string;
  };
  parts: ChatMessageRequestPart[];
};

export type SelectionCommentSnapshotCaptureResult =
  | {
      status: 'available';
      path: string;
      mimeType: 'image/png';
      sizeBytes: number;
    }
  | {
      status: 'unavailable';
    };

export type BridgeSessionEvent =
  | {
      type: 'select_widget_mode_snapshot' | 'select_widget_mode_changed';
      sessionId: string;
      payload: {
        known?: boolean;
        enabled?: boolean;
      };
    }
  | {
      type: 'chat_snapshot';
      sessionId: string;
      payload: {
        agentStatus: AgentStatusResponse;
        messages: ChatMessageResponse[];
      };
    }
  | {
      type: 'agent_status_changed';
      sessionId: string;
      payload: {
        agentStatus: AgentStatusResponse;
      };
    }
  | {
      type: 'chat_history_changed';
      sessionId: string;
      payload: {
        messages: ChatMessageResponse[];
      };
    };

export type SelectWidgetBridgeSessionEvent = Extract<
  BridgeSessionEvent,
  { type: 'select_widget_mode_snapshot' | 'select_widget_mode_changed' }
>;

export type ChatBridgeSessionEvent = Exclude<
  BridgeSessionEvent,
  SelectWidgetBridgeSessionEvent
>;

export function isAgentStatusResponse(
  value: unknown,
): value is AgentStatusResponse {
  return (
    value === 'waiting_for_agent' ||
    value === 'agent_ready' ||
    value === 'agent_working'
  );
}
