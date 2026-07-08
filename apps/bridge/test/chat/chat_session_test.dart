import 'package:ask_ui_bridge/chat/chat_session.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('Bridge Session Chat state', () {
    test('stores Chat History and Agent Status in session memory', () {
      final SessionStore sessionStore = SessionStore();
      final BridgeSession session = sessionStore.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
        clientId: 'browser-1',
      );

      session.chat.appendMessage(
        const ChatMessage(
          id: 'message-1',
          role: ChatMessageRole.agent,
          text: 'Ready to help.',
        ),
      );
      session.chat.setAgentStatus(AgentStatus.agentReady);

      expect(session.chat.snapshot().toJson(), {
        'status': 'ok',
        'agentStatus': 'agent_ready',
        'messages': [
          {
            'id': 'message-1',
            'role': 'agent',
            'text': 'Ready to help.',
          },
        ],
      });
    });

    test('does not restore Chat History after Bridge Session destruction', () {
      final SessionStore firstStore = SessionStore();
      final BridgeSession firstSession = firstStore.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
        clientId: 'browser-1',
      );
      firstSession.chat.appendMessage(
        const ChatMessage(
          id: 'message-1',
          role: ChatMessageRole.user,
          text: 'Change this button.',
        ),
      );

      final SessionStore restartedStore = SessionStore();
      final BridgeSession restartedSession = restartedStore.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
        clientId: 'browser-1',
      );

      expect(restartedSession.chat.snapshot().messages, isEmpty);
      expect(
        restartedSession.chat.snapshot().agentStatus,
        AgentStatus.waitingForAgent,
      );
    });

    test('emits Agent Status and Chat History updates to watchers', () async {
      final ChatSession chat = ChatSession();
      final List<ChatSessionEvent> events = <ChatSessionEvent>[];
      final subscription = chat.events.listen(events.add);
      addTearDown(subscription.cancel);

      chat.setAgentStatus(AgentStatus.agentWorking);
      chat.appendMessage(
        const ChatMessage(
          id: 'message-1',
          role: ChatMessageRole.system,
          text: 'Agent command failed.',
        ),
      );

      await pumpEventQueue();

      expect(events.map((event) => event.toJson()), [
        {
          'type': 'agent_status_changed',
          'payload': {'agentStatus': 'agent_working'},
        },
        {
          'type': 'chat_history_changed',
          'payload': {
            'messages': [
              {
                'id': 'message-1',
                'role': 'system',
                'text': 'Agent command failed.',
              },
            ],
          },
        },
      ]);
    });

    test('reports Agent ready while an Agent Session waits for Chat', () async {
      final ChatSession chat = ChatSession();

      final Future<AgentPollResult> poll = chat.waitForAgentMessage(
        timeout: const Duration(milliseconds: 1),
      );

      expect(chat.snapshot().agentStatus, AgentStatus.agentReady);
      expect(await poll, const AgentPollResult.timedOut());
      expect(chat.snapshot().agentStatus, AgentStatus.waitingForAgent);
    });

    test('rejects a second waiting Agent Session', () async {
      final ChatSession chat = ChatSession();

      final Future<AgentPollResult> poll = chat.waitForAgentMessage(
        timeout: const Duration(milliseconds: 1),
      );

      expect(
        () =>
            chat.waitForAgentMessage(timeout: const Duration(milliseconds: 1)),
        throwsA(isA<AgentPollAlreadyActive>()),
      );
      expect(await poll, const AgentPollResult.timedOut());
    });

    test('returns the current Chat message to the waiting Agent Session',
        () async {
      final ChatSession chat = ChatSession();

      final Future<AgentPollResult> poll = chat.waitForAgentMessage();
      final bool delivered = chat.deliverMessageToAgent(
        const ChatMessage(
          id: 'message-1',
          role: ChatMessageRole.user,
          text: 'Make this button primary.',
        ),
      );

      expect(delivered, isTrue);
      expect((await poll).toJson(), {
        'status': 'ok',
        'message': {
          'id': 'message-1',
          'role': 'user',
          'text': 'Make this button primary.',
        },
        'nextStep':
            'Process this Chat message, write an agent reply or system error, then poll again.',
      });
      expect(chat.snapshot().messages.map((message) => message.toJson()), [
        {
          'id': 'message-1',
          'role': 'user',
          'text': 'Make this button primary.',
        },
      ]);
    });

    test('returns to Waiting for agent when the waiting Agent disconnects',
        () async {
      final ChatSession chat = ChatSession();

      final Future<AgentPollResult> poll = chat.waitForAgentMessage();
      expect(chat.snapshot().agentStatus, AgentStatus.agentReady);

      chat.cancelAgentWait();

      expect(await poll, const AgentPollResult.timedOut());
      expect(chat.snapshot().agentStatus, AgentStatus.waitingForAgent);
    });

    test('stores agent replies with a top-level user reply-to id', () async {
      final ChatSession chat = ChatSession();
      final Future<AgentPollResult> poll = chat.waitForAgentMessage();
      final ChatMessage? userMessage = chat.sendUserTextMessage(
        'Make this button primary.',
      );
      await poll;

      final ChatMessage reply = chat.appendAgentReply(
        '  Done.  ',
        replyToMessageId: userMessage?.id,
      );

      expect(reply.toJson(), {
        'id': 'message-2',
        'role': 'agent',
        'text': '  Done.  ',
        'replyToMessageId': 'message-1',
      });
      expect(
        () => chat.appendAgentReply('Missing correlation.'),
        throwsA(isA<InvalidReplyToMessage>()),
      );
    });

    test('stores optional system reply-to ids for existing user messages',
        () async {
      final ChatSession chat = ChatSession();
      final Future<AgentPollResult> poll = chat.waitForAgentMessage();
      final ChatMessage? userMessage = chat.sendUserTextMessage(
        'Make this button primary.',
      );
      await poll;

      final ChatMessage sessionError = chat.appendAgentError(
        'Session setup failed.',
      );
      final ChatMessage workflowError = chat.appendAgentError(
        'Could not run tests.',
        replyToMessageId: userMessage?.id,
      );
      final ChatMessage followUp = chat.appendAgentReply(
        'I fixed the layout manually.',
        replyToMessageId: userMessage?.id,
      );

      expect(sessionError.toJson(), {
        'id': 'message-2',
        'role': 'system',
        'text': 'Session setup failed.',
      });
      expect(workflowError.toJson(), {
        'id': 'message-3',
        'role': 'system',
        'text': 'Could not run tests.',
        'replyToMessageId': 'message-1',
      });
      expect(followUp.toJson(), {
        'id': 'message-4',
        'role': 'agent',
        'text': 'I fixed the layout manually.',
        'replyToMessageId': 'message-1',
      });
      expect(
        () => chat.appendAgentError(
          'Bad target.',
          replyToMessageId: 'message-404',
        ),
        throwsA(isA<InvalidReplyToMessage>()),
      );
      expect(
        () => chat.appendAgentError(
          'System messages are not valid targets.',
          replyToMessageId: workflowError.id,
        ),
        throwsA(isA<InvalidReplyToMessage>()),
      );
    });
  });
}
