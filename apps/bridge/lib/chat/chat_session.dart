import 'dart:async';

/// Agent availability shown in the Chat panel.
///
/// The status belongs to one Bridge Session and starts as
/// `waitingForAgent`. Later issues move it to `agentReady` when an Agent
/// Session poller is waiting and `agentWorking` while the agent handles a
/// delivered Chat message.
enum AgentStatus {
  waitingForAgent('waiting_for_agent'),
  agentReady('agent_ready'),
  agentWorking('agent_working');

  const AgentStatus(this.wireName);

  final String wireName;
}

/// Role for one persisted Chat History message.
///
/// Issue 2 only stores and serializes messages. Later slices append user,
/// agent, and system messages through send/reply endpoints.
enum ChatMessageRole {
  user('user'),
  agent('agent'),
  system('system');

  const ChatMessageRole(this.wireName);

  final String wireName;
}

/// One message in Bridge Session Chat History.
///
/// It carries the stable message id, the role displayed by the web Chat
/// History, and plain text content. Attachment summaries are added in a later
/// Selection Chat slice.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
  });

  final String id;
  final ChatMessageRole role;
  final String text;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'role': role.wireName,
      'text': text,
    };
  }
}

/// Immutable snapshot returned to the web Chat panel.
///
/// The snapshot is session-scoped and in-memory. Creating a new `SessionStore`
/// creates new `BridgeSession` objects and therefore empty Chat snapshots.
class ChatSessionSnapshot {
  const ChatSessionSnapshot({
    required this.agentStatus,
    required this.messages,
  });

  final AgentStatus agentStatus;
  final List<ChatMessage> messages;

  Map<String, Object?> toJson({bool? readOnly}) {
    return {
      'status': 'ok',
      'agentStatus': agentStatus.wireName,
      'messages': messages.map((message) => message.toJson()).toList(),
      if (readOnly != null) 'readOnly': readOnly,
    };
  }
}

/// Chat update event emitted by one Bridge Session.
///
/// Events are broadcast to `/api/sessions/{sessionId}/events`, reusing the
/// existing Bridge Session SSE stream instead of adding a Chat-specific socket.
class ChatSessionEvent {
  const ChatSessionEvent._({
    required this.type,
    required this.payload,
  });

  factory ChatSessionEvent.agentStatusChanged(AgentStatus status) {
    return ChatSessionEvent._(
      type: 'agent_status_changed',
      payload: {
        'agentStatus': status.wireName,
      },
    );
  }

  factory ChatSessionEvent.chatHistoryChanged(List<ChatMessage> messages) {
    return ChatSessionEvent._(
      type: 'chat_history_changed',
      payload: {
        'messages': messages.map((message) => message.toJson()).toList(),
      },
    );
  }

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return {
      'type': type,
      'payload': payload,
    };
  }
}

/// In-memory Chat state for one Bridge Session.
///
/// It owns Chat History and Agent Status until the bridge backend stops or the
/// session store is destroyed. It exposes snapshots for initial page loads and
/// broadcast events for already-open browser tabs.
class ChatSession {
  final List<ChatMessage> _messages = <ChatMessage>[];
  final StreamController<ChatSessionEvent> _eventsController =
      StreamController<ChatSessionEvent>.broadcast();
  AgentStatus _agentStatus = AgentStatus.waitingForAgent;

  Stream<ChatSessionEvent> get events => _eventsController.stream;

  ChatSessionSnapshot snapshot() {
    return ChatSessionSnapshot(
      agentStatus: _agentStatus,
      messages: List<ChatMessage>.unmodifiable(_messages),
    );
  }

  void setAgentStatus(AgentStatus status) {
    if (_agentStatus == status) {
      return;
    }

    _agentStatus = status;
    _eventsController.add(ChatSessionEvent.agentStatusChanged(status));
  }

  void appendMessage(ChatMessage message) {
    _messages.add(message);
    _eventsController.add(
      ChatSessionEvent.chatHistoryChanged(
        List<ChatMessage>.unmodifiable(_messages),
      ),
    );
  }
}
