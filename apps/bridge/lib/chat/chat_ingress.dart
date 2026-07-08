import '../sessions/session_store.dart';

const int _chatMessageTextLimit = 4000;
const int _selectionCommentTextLimit = 1000;
const int _selectionCommentMetadataLimit = 1000;
const int _selectionCommentBatchLimit = 20;

class ChatIngress {
  const ChatIngress({
    required bool Function(String path) snapshotFileExists,
  }) : _snapshotFileExists = snapshotFileExists;

  final bool Function(String path) _snapshotFileExists;

  ChatIngressMessage parseMessage(
    Map<String, Object?> body,
    BridgeSession session,
  ) {
    final Object? text = body['text'];
    if (text is String) {
      if (text.trim().isEmpty) {
        return const RejectedChatIngressMessage('empty_chat_message');
      }
      if (text.length > _chatMessageTextLimit) {
        return const RejectedChatIngressMessage('chat_message_too_long');
      }

      return AcceptedChatIngressMessage(text: text);
    }

    final Object? rawParts = body['parts'];
    if (rawParts is! List<Object?> || rawParts.isEmpty) {
      return const RejectedChatIngressMessage('empty_chat_message');
    }
    if (rawParts.length > _selectionCommentBatchLimit + 1) {
      return const RejectedChatIngressMessage('invalid_chat_parts');
    }

    final List<Map<String, Object?>> parts = <Map<String, Object?>>[];
    String typedText = '';
    int selectionCommentCount = 0;
    int textPartCount = 0;
    for (final rawPart in rawParts) {
      final Map<String, Object?>? part = _normalizeJsonObject(rawPart);
      if (part == null) {
        return const RejectedChatIngressMessage('invalid_chat_parts');
      }

      final normalizedPart = _parseChatMessagePart(part, session);
      if (normalizedPart == null) {
        return const RejectedChatIngressMessage('invalid_chat_parts');
      }

      if (normalizedPart['type'] == 'text') {
        textPartCount += 1;
        typedText = normalizedPart['text'] as String;
      } else {
        selectionCommentCount += 1;
      }

      parts.add(normalizedPart);
    }

    if (typedText.length > _chatMessageTextLimit ||
        textPartCount > 1 ||
        selectionCommentCount > _selectionCommentBatchLimit) {
      return const RejectedChatIngressMessage('invalid_chat_parts');
    }

    final bool hasAttachment = parts.any(
      (part) => part['type'] == 'selection_comment',
    );
    if (!hasAttachment && typedText.trim().isEmpty) {
      return const RejectedChatIngressMessage('empty_chat_message');
    }

    return AcceptedChatIngressMessage(
      text: typedText,
      context: {'projectRoot': session.projectRoot},
      parts: parts,
    );
  }

  Map<String, Object?>? _parseChatMessagePart(
    Map<String, Object?> part,
    BridgeSession session,
  ) {
    switch (part['type']) {
      case 'text':
        final text = part['text'];
        if (text is! String) {
          return null;
        }
        return {
          'type': 'text',
          'text': text,
        };
      case 'selection_comment':
        final attachment = _normalizeJsonObject(part['attachment']);
        if (attachment == null) {
          return null;
        }
        final normalizedAttachment =
            _parseSelectionCommentAttachment(attachment, session);
        if (normalizedAttachment == null) {
          return null;
        }
        return {
          'type': 'selection_comment',
          'attachment': normalizedAttachment,
        };
    }

    return null;
  }

  Map<String, Object?>? _parseSelectionCommentAttachment(
    Map<String, Object?> attachment,
    BridgeSession session,
  ) {
    final id = attachment['id'];
    final commentText = attachment['commentText'];
    final selectedWidget = _normalizeJsonObject(attachment['selectedWidget']);
    final snapshot = _normalizeJsonObject(attachment['snapshot']);
    if (!_isBoundedNonBlankString(id, _selectionCommentMetadataLimit) ||
        !_isBoundedNonBlankString(commentText, _selectionCommentTextLimit) ||
        selectedWidget == null ||
        snapshot == null) {
      return null;
    }

    final normalizedSelectedWidget = _parseSelectedWidget(selectedWidget);
    final normalizedSnapshot = _parseSelectionCommentSnapshot(
      snapshot,
      session,
    );
    if (normalizedSelectedWidget == null || normalizedSnapshot == null) {
      return null;
    }

    return {
      'id': id,
      'commentText': commentText,
      'selectedWidget': normalizedSelectedWidget,
      'snapshot': normalizedSnapshot,
    };
  }

  Map<String, Object?>? _parseSelectedWidget(Map<String, Object?> widget) {
    final id = widget['id'];
    final displayLabel = widget['displayLabel'];
    if (!_isBoundedNonBlankString(id, _selectionCommentMetadataLimit) ||
        !_isBoundedNonBlankString(
          displayLabel,
          _selectionCommentMetadataLimit,
        )) {
      return null;
    }

    final normalized = <String, Object?>{
      'id': id,
      'displayLabel': displayLabel,
    };
    for (final key in ['sourceLocation', 'visibleText', 'semanticInfo']) {
      final value = widget[key];
      if (value != null) {
        if (!_isBoundedString(value, _selectionCommentTextLimit)) {
          return null;
        }
        normalized[key] = value;
      }
    }
    return normalized;
  }

  Map<String, Object?>? _parseSelectionCommentSnapshot(
    Map<String, Object?> snapshot,
    BridgeSession session,
  ) {
    switch (snapshot['status']) {
      case 'available':
        final path = snapshot['path'];
        if (!_isBoundedNonBlankString(path, _selectionCommentMetadataLimit) ||
            !_snapshotFileExists(path as String) ||
            !session.ownsManagedLocalPath(path)) {
          return null;
        }
        return {
          'status': 'available',
          'path': path,
        };
      case 'unavailable':
        return {'status': 'unavailable'};
    }

    return null;
  }
}

abstract class ChatIngressMessage {
  const ChatIngressMessage();
}

class AcceptedChatIngressMessage extends ChatIngressMessage {
  const AcceptedChatIngressMessage({
    required this.text,
    this.context = const <String, Object?>{},
    this.parts = const <Map<String, Object?>>[],
  });

  final String text;
  final Map<String, Object?> context;
  final List<Map<String, Object?>> parts;
}

class RejectedChatIngressMessage extends ChatIngressMessage {
  const RejectedChatIngressMessage(this.error);

  final String error;
}

bool _isBoundedNonBlankString(Object? value, int limit) {
  if (value is! String) {
    return false;
  }
  return value.trim().isNotEmpty && value.length <= limit;
}

bool _isBoundedString(Object? value, int limit) {
  return value is String && value.length <= limit;
}

Map<String, Object?>? _normalizeJsonObject(Object? value) {
  if (value is! Map) {
    return null;
  }

  final Map<String, Object?> normalized = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      return null;
    }
    normalized[key] = _normalizeJsonValue(entry.value);
  }
  return normalized;
}

Object? _normalizeJsonValue(Object? value) {
  if (value is Map) {
    final Map<String, Object?> normalized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        normalized[key] = _normalizeJsonValue(entry.value);
      }
    }
    return normalized;
  }

  if (value is List) {
    return value.map(_normalizeJsonValue).toList();
  }

  return value;
}
