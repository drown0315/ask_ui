import 'package:ask_ui_bridge/chat/chat_ingress.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('ChatIngress', () {
    late BridgeSession session;
    late Set<String> existingSnapshotPaths;
    late ChatIngress ingress;

    setUp(() {
      session = BridgeSession(
        id: 'session-1',
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );
      existingSnapshotPaths = <String>{};
      ingress = ChatIngress(
        snapshotFileExists: existingSnapshotPaths.contains,
      );
    });

    test('accepts plain text Chat requests', () {
      final result = ingress.parseMessage(
        {'text': 'Make this button primary.'},
        session,
      );

      expect(result, isA<AcceptedChatIngressMessage>());
      final accepted = result as AcceptedChatIngressMessage;
      expect(accepted.text, 'Make this button primary.');
      expect(accepted.context, isEmpty);
      expect(accepted.parts, isEmpty);
    });

    test('accepts ordered Selection Comment attachments', () {
      final result = ingress.parseMessage(
        {
          'parts': [
            {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-1',
                'commentText': 'Make this button primary.',
                'selectedWidget': {
                  'id': 'widget-1',
                  'displayLabel': 'PrimaryButton',
                  'sourceLocation': 'lib/home.dart:12:4',
                  'visibleText': 'Save',
                  'semanticInfo': 'button',
                },
                'snapshot': {'status': 'unavailable'},
              },
            },
            {
              'type': 'text',
              'text': 'Please update this screen.',
            },
          ],
        },
        session,
      );

      expect(result, isA<AcceptedChatIngressMessage>());
      final accepted = result as AcceptedChatIngressMessage;
      expect(accepted.text, 'Please update this screen.');
      expect(accepted.context, {'projectRoot': '/Users/example/app'});
      expect(accepted.parts, [
        {
          'type': 'selection_comment',
          'attachment': {
            'id': 'selection-comment-1',
            'commentText': 'Make this button primary.',
            'selectedWidget': {
              'id': 'widget-1',
              'displayLabel': 'PrimaryButton',
              'sourceLocation': 'lib/home.dart:12:4',
              'visibleText': 'Save',
              'semanticInfo': 'button',
            },
            'snapshot': {'status': 'unavailable'},
          },
        },
        {
          'type': 'text',
          'text': 'Please update this screen.',
        },
      ]);
    });

    test('rejects invalid part shapes', () {
      final missingAttachment = ingress.parseMessage(
        {
          'parts': [
            {'type': 'selection_comment'},
          ],
        },
        session,
      );
      final repeatedText = ingress.parseMessage(
        {
          'parts': [
            {'type': 'text', 'text': 'First.'},
            {'type': 'text', 'text': 'Second.'},
          ],
        },
        session,
      );

      expect(missingAttachment, isA<RejectedChatIngressMessage>());
      expect(
        (missingAttachment as RejectedChatIngressMessage).error,
        'invalid_chat_parts',
      );
      expect(repeatedText, isA<RejectedChatIngressMessage>());
      expect(
        (repeatedText as RejectedChatIngressMessage).error,
        'invalid_chat_parts',
      );
    });

    test('enforces text, metadata, and batch limits', () {
      final longPlainText = ingress.parseMessage(
        {'text': List.filled(4001, 'x').join()},
        session,
      );
      final longSelectionText = ingress.parseMessage(
        {
          'parts': [
            {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-1',
                'commentText': List.filled(1001, 'x').join(),
                'selectedWidget': {
                  'id': 'widget-1',
                  'displayLabel': 'PrimaryButton',
                },
                'snapshot': {'status': 'unavailable'},
              },
            },
          ],
        },
        session,
      );
      final tooManyAttachments = ingress.parseMessage(
        {
          'parts': List<Object?>.generate(
            21,
            (index) => {
              'type': 'selection_comment',
              'attachment': {
                'id': 'selection-comment-$index',
                'commentText': 'Comment $index',
                'selectedWidget': {
                  'id': 'widget-$index',
                  'displayLabel': 'Widget$index',
                },
                'snapshot': {'status': 'unavailable'},
              },
            },
          ),
        },
        session,
      );

      expect(
        (longPlainText as RejectedChatIngressMessage).error,
        'chat_message_too_long',
      );
      expect(
        (longSelectionText as RejectedChatIngressMessage).error,
        'invalid_chat_parts',
      );
      expect(
        (tooManyAttachments as RejectedChatIngressMessage).error,
        'invalid_chat_parts',
      );
    });

    test('requires available snapshots to belong to the Bridge Session', () {
      const snapshotPath = '/tmp/ask-ui/session-1/snapshots/comment.png';
      existingSnapshotPaths.add(snapshotPath);

      final unowned = ingress.parseMessage(
        {
          'parts': [
            selectionCommentPart(snapshotPath),
          ],
        },
        session,
      );

      session.manageLocalPath('/tmp/ask-ui/session-1');
      final owned = ingress.parseMessage(
        {
          'parts': [
            selectionCommentPart(snapshotPath),
          ],
        },
        session,
      );

      expect(
          (unowned as RejectedChatIngressMessage).error, 'invalid_chat_parts');
      expect(owned, isA<AcceptedChatIngressMessage>());
    });

    test('does not restore snapshot ownership in a restarted Bridge Session',
        () {
      const snapshotPath = '/tmp/ask-ui/session-1/snapshots/comment.png';
      existingSnapshotPaths.add(snapshotPath);
      session.manageLocalPath('/tmp/ask-ui/session-1');
      final originalSessionResult = ingress.parseMessage(
        {
          'parts': [
            selectionCommentPart(snapshotPath),
          ],
        },
        session,
      );
      final restartedSession = BridgeSession(
        id: 'session-1',
        vmServiceUri: session.vmServiceUri,
        projectRoot: session.projectRoot,
        deviceId: session.deviceId,
      );

      final restartedSessionResult = ingress.parseMessage(
        {
          'parts': [
            selectionCommentPart(snapshotPath),
          ],
        },
        restartedSession,
      );

      expect(originalSessionResult, isA<AcceptedChatIngressMessage>());
      expect(
        (restartedSessionResult as RejectedChatIngressMessage).error,
        'invalid_chat_parts',
      );
    });
  });
}

Map<String, Object?> selectionCommentPart(String snapshotPath) {
  return {
    'type': 'selection_comment',
    'attachment': {
      'id': 'selection-comment-1',
      'commentText': 'Make this button primary.',
      'selectedWidget': {
        'id': 'widget-1',
        'displayLabel': 'PrimaryButton',
      },
      'snapshot': {
        'status': 'available',
        'path': snapshotPath,
      },
    },
  };
}
