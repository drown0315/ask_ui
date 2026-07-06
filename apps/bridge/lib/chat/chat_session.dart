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
/// User messages come from the browser composer, agent messages are normal
/// Agent Session replies, and system messages represent command-level agent
/// errors.
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
/// History, and plain text content. Selection Comment attachments are added to
/// message payloads in a later Selection Chat slice.
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

/// Result returned to an Agent Session long-poll request.
///
/// A timed out result is used only by tests or debugging clients that pass an
/// explicit timeout. Product polling keeps waiting until a Chat message is
/// available or the request disconnects.
class AgentPollResult {
  const AgentPollResult.timedOut()
      : timedOut = true,
        message = null;

  const AgentPollResult.message(ChatMessage this.message) : timedOut = false;

  final bool timedOut;
  final ChatMessage? message;

  Map<String, Object?> toJson() {
    return {
      'status': timedOut ? 'timeout' : 'ok',
      'message': message?.toJson(),
      'nextStep': AgentPollResult.nextStepInstruction,
    };
  }

  static const String nextStepInstruction =
      'Process this Chat message, write an agent reply or system error, then poll again.';

  @override
  bool operator ==(Object other) {
    return other is AgentPollResult &&
        timedOut == other.timedOut &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(timedOut, message);
}

/// Raised when one Bridge Session already has a waiting Agent Session.
class AgentPollAlreadyActive implements Exception {
  const AgentPollAlreadyActive();

  @override
  String toString() => 'AgentPollAlreadyActive';
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
  Completer<AgentPollResult>? _activePoll;
  int _nextMessageNumber = 1;

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

  /// Create and deliver one user Chat message to the waiting Agent Session.
  ///
  /// Returns `null` when no Agent Session is ready. The message is appended to
  /// Chat History only after the active poller has accepted the handoff.
  ChatMessage? sendUserTextMessage(String text) {
    final ChatMessage message = ChatMessage(
      id: _createMessageId(),
      role: ChatMessageRole.user,
      text: text,
    );

    if (!deliverMessageToAgent(message)) {
      return null;
    }

    return message;
  }

  /// Append one successful agent reply to Chat History.
  ///
  /// A reply completes the current agent work item from the web UI's
  /// perspective. The launching Agent Session may start another poll after the
  /// reply has been stored.
  ChatMessage appendAgentReply(String text) {
    return _appendAgentAuthoredMessage(
      role: ChatMessageRole.agent,
      text: text,
    );
  }

  /// Append one agent command error as a system Chat History message.
  ///
  /// Command-level failures are separated from normal agent replies so the
  /// product UI can distinguish tool/session failures from agent prose.
  ChatMessage appendAgentError(String text) {
    return _appendAgentAuthoredMessage(
      role: ChatMessageRole.system,
      text: text,
    );
  }

  ChatMessage _appendAgentAuthoredMessage({
    required ChatMessageRole role,
    required String text,
  }) {
    final ChatMessage message = ChatMessage(
      id: _createMessageId(),
      role: role,
      text: text,
    );
    appendMessage(message);
    setAgentStatus(AgentStatus.waitingForAgent);
    return message;
  }

  String _createMessageId() {
    final String id = 'message-$_nextMessageNumber';
    _nextMessageNumber += 1;
    return id;
  }

  /// Wait for the next Chat message for the launching Agent Session.
  ///
  /// Only one Agent Session may wait on a Bridge Session at a time. Passing a
  /// timeout is intended for tests and debugging; omitting it creates the
  /// indefinite long-poll used by the normal skill loop.
  Future<AgentPollResult> waitForAgentMessage({Duration? timeout}) {
    if (_activePoll != null) {
      throw const AgentPollAlreadyActive();
    }

    final Completer<AgentPollResult> poll = Completer<AgentPollResult>();
    _activePoll = poll;
    setAgentStatus(AgentStatus.agentReady);

    if (timeout != null) {
      Timer(timeout, () {
        if (_activePoll != poll || poll.isCompleted) {
          return;
        }

        poll.complete(const AgentPollResult.timedOut());
      });
    }

    return poll.future.whenComplete(() {
      if (_activePoll == poll) {
        _activePoll = null;
        setAgentStatus(AgentStatus.waitingForAgent);
      }
    });
  }

  /// Deliver one Chat message to the currently waiting Agent Session.
  ///
  /// Returns `false` when no Agent Session is ready, allowing the later Send API
  /// to reject the browser request without creating an offline queue.
  bool deliverMessageToAgent(ChatMessage message) {
    final Completer<AgentPollResult>? poll = _activePoll;
    if (poll == null || poll.isCompleted) {
      return false;
    }

    appendMessage(message);
    _activePoll = null;
    setAgentStatus(AgentStatus.agentWorking);
    poll.complete(AgentPollResult.message(message));
    return true;
  }

  /// Cancel the waiting Agent Session after its HTTP request disconnects.
  void cancelAgentWait() {
    final Completer<AgentPollResult>? poll = _activePoll;
    if (poll == null || poll.isCompleted) {
      return;
    }

    poll.complete(const AgentPollResult.timedOut());
  }
}
