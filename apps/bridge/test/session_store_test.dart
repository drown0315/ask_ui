import 'dart:io';

import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:file_testkit/file_testkit.dart';
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
        deviceDisplayName: 'Pixel 6',
      );
      final secondSession = store.createSession(
        vmServiceUri: '  ws://127.0.0.1:12345/ws  ',
        projectRoot: '  /Users/example/app  ',
        deviceId: '  19271FDF6007TY  ',
        deviceDisplayName: 'Updated Pixel 6',
      );

      expect(secondSession, same(firstSession));
      expect(secondSession.id, firstSession.id);
      expect(secondSession.deviceDisplayName, 'Updated Pixel 6');
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

    test('destroys managed local session files', () async {
      await FileTestkit.runZoned(() async {
        final store = SessionStore();
        final session = store.createSession(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: 'device-1',
        );
        final directory = Directory('/ask-ui-session-store-test');
        await directory.create();
        final snapshotFile = File('${directory.path}/selection-comment-1.png');
        await snapshotFile.writeAsBytes([1, 2, 3]);
        session.manageLocalPath(directory.path);

        await store.destroyAll();

        expect(store.sessionCount, 0);
        expect(await directory.exists(), isFalse);
        expect(store.find(session.id), isNull);
      });
    });

    test('matches managed local paths by normalized path segment', () {
      final store = SessionStore();
      final session = store.createSession(
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: 'device-1',
      );

      session.manageLocalPath('/tmp/ask-ui-snapshots/session-1');

      expect(
        session.ownsManagedLocalPath(
          '/tmp/ask-ui-snapshots/session-1/snapshots/comment.png',
        ),
        isTrue,
      );
      expect(
        session.ownsManagedLocalPath(
          '/tmp/ask-ui-snapshots/session-1/../session-2/snapshot.png',
        ),
        isFalse,
      );
      expect(
        session.ownsManagedLocalPath(
          '/tmp/ask-ui-snapshots/session-10/snapshot.png',
        ),
        isFalse,
      );
    });
  });
}
