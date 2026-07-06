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
  });
}
