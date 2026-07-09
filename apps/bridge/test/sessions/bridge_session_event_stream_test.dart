import 'dart:async';
import 'dart:convert';

import 'package:ask_ui_bridge/chat/chat_session.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/sessions/bridge_session_event_stream.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:ask_ui_bridge/widget_tree/widget_tree_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('BridgeSessionEventStream', () {
    late BridgeSession session;
    late RecordingInspectorClient inspectorClient;
    late RecordingSseTransport transport;
    late List<String> logs;

    setUp(() {
      session = BridgeSession(
        id: 'session-1',
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );
      inspectorClient = RecordingInspectorClient();
      transport = RecordingSseTransport();
      logs = <String>[];
    });

    BridgeSessionEventStream eventStream({
      Duration heartbeatInterval = const Duration(seconds: 15),
    }) {
      return BridgeSessionEventStream(
        inspectorClient: inspectorClient,
        heartbeatInterval: heartbeatInterval,
        logger: BridgeLogger(write: logs.add),
      );
    }

    test('writes initial Select Widget and Chat snapshots', () async {
      inspectorClient.selectWidgetModeStatus = true;

      await eventStream().open(session: session, transport: transport);

      expect(transport.events, [
        SseWrite(
          event: 'bridge_session_event',
          data: {
            'type': 'select_widget_mode_snapshot',
            'sessionId': 'session-1',
            'payload': {
              'known': true,
              'enabled': true,
            },
          },
        ),
        SseWrite(
          event: 'bridge_session_event',
          data: {
            'type': 'chat_snapshot',
            'sessionId': 'session-1',
            'payload': {
              'agentStatus': 'waiting_for_agent',
              'messages': <Object?>[],
            },
          },
        ),
      ]);
    });

    test('forwards Select Widget, Widget Selection, and Chat updates',
        () async {
      await eventStream().open(session: session, transport: transport);
      transport.events.clear();

      inspectorClient.emitSelectWidgetMode(true);
      inspectorClient.emitWidgetSelection('inspector-2');
      session.chat.setAgentStatus(AgentStatus.agentReady);

      await waitForEventCount(transport, 3);

      expect(transport.events, [
        SseWrite(
          event: 'bridge_session_event',
          data: {
            'type': 'select_widget_mode_changed',
            'sessionId': 'session-1',
            'payload': {'enabled': true},
          },
        ),
        SseWrite(
          event: 'bridge_session_event',
          data: {
            'type': 'widget_selection_changed',
            'sessionId': 'session-1',
            'payload': {'widgetId': 'inspector-2'},
          },
        ),
        SseWrite(
          event: 'bridge_session_event',
          data: {
            'type': 'agent_status_changed',
            'payload': {'agentStatus': 'agent_ready'},
            'sessionId': 'session-1',
          },
        ),
      ]);
    });

    test('writes heartbeats through the serialized queue', () async {
      await eventStream(
        heartbeatInterval: const Duration(milliseconds: 10),
      ).open(session: session, transport: transport);

      await waitForHeartbeat(transport);

      expect(transport.heartbeats, isNotEmpty);
      expect(transport.maxConcurrentFlushes, 1);
    });

    test('cancels subscriptions and heartbeat on disconnect', () async {
      await eventStream(
        heartbeatInterval: const Duration(milliseconds: 10),
      ).open(session: session, transport: transport);
      transport.events.clear();
      transport.heartbeats.clear();

      await transport.closeFromBrowser();
      inspectorClient.emitSelectWidgetMode(true);
      session.chat.setAgentStatus(AgentStatus.agentReady);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(transport.events, isEmpty);
      expect(transport.heartbeats, isEmpty);
      expect(
        logs,
        contains('[ask_ui_bridge] events stream session=session-1 close'),
      );
    });

    test('returns a typed failure when Select Widget snapshot fails', () async {
      inspectorClient.failure = StateError('inspector exploded');

      final result = await eventStream().open(
        session: session,
        transport: transport,
      );

      expect(result, isA<BridgeSessionEventStreamFailure>());
      expect(
        (result as BridgeSessionEventStreamFailure).error,
        'session_events_failed',
      );
      expect(transport.events, isEmpty);
    });
  });
}

Future<void> waitForEventCount(
    RecordingSseTransport transport, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (transport.events.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected at least $count SSE events.');
}

Future<void> waitForHeartbeat(RecordingSseTransport transport) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (transport.heartbeats.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected heartbeat.');
}

class RecordingSseTransport implements BridgeSessionEventTransport {
  final _done = Completer<void>();
  final events = <SseWrite>[];
  final heartbeats = <String>[];
  int activeFlushes = 0;
  int maxConcurrentFlushes = 0;
  bool started = false;

  @override
  Future<void> get done => _done.future;

  @override
  void start() {
    started = true;
  }

  @override
  void writeEvent({
    required String event,
    required Map<String, Object?> data,
  }) {
    events.add(SseWrite(event: event, data: data));
  }

  @override
  void writeComment(String comment) {
    heartbeats.add(comment);
  }

  @override
  Future<void> flush() async {
    activeFlushes += 1;
    maxConcurrentFlushes = maxConcurrentFlushes < activeFlushes
        ? activeFlushes
        : maxConcurrentFlushes;
    await Future<void>.delayed(Duration.zero);
    activeFlushes -= 1;
  }

  Future<void> closeFromBrowser() async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

class SseWrite {
  const SseWrite({
    required this.event,
    required this.data,
  });

  final String event;
  final Map<String, Object?> data;

  @override
  bool operator ==(Object other) {
    return other is SseWrite &&
        other.event == event &&
        jsonEncode(other.data) == jsonEncode(data);
  }

  @override
  int get hashCode => Object.hash(event, jsonEncode(data));

  @override
  String toString() => 'SseWrite(event: $event, data: $data)';
}

class RecordingInspectorClient implements FlutterInspectorClient {
  final _controller = StreamController<SelectWidgetModeStatus>.broadcast();
  final _widgetSelectionController =
      StreamController<WidgetSelectionStatus>.broadcast();
  bool? selectWidgetModeStatus;
  Object? failure;

  @override
  Future<SelectWidgetModeStatus> getSelectWidgetModeStatus(
    BridgeSession session,
  ) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return SelectWidgetModeStatus(enabled: selectWidgetModeStatus);
  }

  @override
  Stream<SelectWidgetModeStatus> watchSelectWidgetModeStatus(
    BridgeSession session,
  ) {
    return _controller.stream;
  }

  void emitSelectWidgetMode(bool enabled) {
    _controller.add(SelectWidgetModeStatus(enabled: enabled));
  }

  @override
  Stream<WidgetSelectionStatus> watchWidgetSelectionStatus(
    BridgeSession session,
  ) {
    return _widgetSelectionController.stream;
  }

  void emitWidgetSelection(String widgetId) {
    _widgetSelectionController.add(WidgetSelectionStatus(widgetId: widgetId));
  }

  @override
  Future<WidgetTreeNode> fetchRootWidgetTree(BridgeSession session) {
    throw UnimplementedError();
  }

  @override
  Future<SelectWidgetModeResult> setSelectWidgetMode(
    BridgeSession session, {
    required bool enabled,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<WidgetSelectionResult> selectWidgetById(
    BridgeSession session, {
    required String widgetId,
  }) {
    throw UnimplementedError();
  }
}
