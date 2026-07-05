import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('SessionStore', () {
    test('creates a session from vmServiceUri and projectRoot', () {
      final store = SessionStore();

      final session = store.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );

      expect(session.id, isNotEmpty);
      expect(session.vmServiceUri, 'ws://127.0.0.1:12345/ws');
      expect(session.projectRoot, '/Users/example/app');
      expect(session.deviceId, '19271FDF6007TY');
      expect(store.find(session.id), same(session));
    });

    test(
        'reuses the existing session for the same vmServiceUri, projectRoot, and deviceId',
        () {
      final store = SessionStore();

      final firstSession = store.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );
      final secondSession = store.createSession(
        vmServiceUri: '  ws://127.0.0.1:12345/ws  ',
        projectRoot: '  /Users/example/app  ',
        deviceId: '  19271FDF6007TY  ',
      );

      expect(secondSession, same(firstSession));
      expect(secondSession.id, firstSession.id);
      expect(store.sessionCount, 1);
    });

    test('rejects blank session parameters', () {
      final store = SessionStore();

      expect(
        () => store.createSession(
            vmServiceUri: '', projectRoot: '/app', deviceId: 'device-1'),
        throwsA(isA<InvalidSessionRequest>()),
      );
      expect(
        () => store.createSession(
            vmServiceUri: 'ws://127.0.0.1/ws',
            projectRoot: '  ',
            deviceId: 'device-1'),
        throwsA(isA<InvalidSessionRequest>()),
      );
      expect(
        () => store.createSession(
            vmServiceUri: 'ws://127.0.0.1/ws',
            projectRoot: '/app',
            deviceId: '  '),
        throwsA(isA<InvalidSessionRequest>()),
      );
    });

    test('rejects a different deviceId for the same Flutter app session', () {
      final store = SessionStore();

      store.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: 'device-1',
      );

      expect(
        () => store.createSession(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: 'device-2',
        ),
        throwsA(isA<DeviceMismatchForSession>()),
      );
      expect(store.sessionCount, 1);
    });
  });
}
