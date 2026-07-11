import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Ask UI launch skill workflow', () {
    test('documents the installed user launch and poll workflow', () {
      final File skillFile = File('../../skills/ask-ui/SKILL.md');

      expect(skillFile.existsSync(), isTrue);
      final String skill = skillFile.readAsStringSync();

      expect(skill, contains('ask_ui'));
      expect(skill, contains('dart pub global activate ask_ui_bridge'));
      expect(skill, contains('ask_ui_bridge launch'));
      expect(skill, contains('ask_ui_runtime'));
      expect(skill, contains('flutter pub add ask_ui_runtime'));
      expect(skill, contains('registerAskUiRuntime'));
      expect(skill, isNot(contains('dart run bin/ask_ui_bridge.dart launch')));
      expect(skill, isNot(contains('--web-dev')));
      _expectCommonAgentLoopContract(skill);
    });

    test('documents the maintainer source launch and Web dev workflow', () {
      final File skillFile = File('../../skills/ask-ui-dev/SKILL.md');

      expect(skillFile.existsSync(), isTrue);
      final String skill = skillFile.readAsStringSync();

      expect(skill, contains('ask-ui-dev'));
      expect(skill, contains('dart run bin/ask_ui_bridge.dart launch'));
      expect(skill, contains('--web-dev'));
      expect(skill, contains('Vite'));
      _expectCommonAgentLoopContract(skill);
    });
  });
}

void _expectCommonAgentLoopContract(String skill) {
  expect(skill, contains('--device <device-id-or-name>'));
  expect(skill, contains('--flavor <flavor>'));
  expect(skill, contains('--target <path>'));
  expect(skill, contains('--dart-define <key=value>'));
  expect(skill, contains('needs_device_selection'));
  expect(skill, contains('suggestedCommand'));
  expect(skill, contains('ready'));
  expect(skill, contains('agentCommand'));
  expect(skill, contains('current-session task input'));
  expect(
    skill,
    contains('agent poll --reply-to <message-id> --agent-reply <text>'),
  );
  expect(skill, contains('--agent-error'));
  expect(skill, contains('continue polling'));
  expect(skill, contains('Do not duplicate'));
  expect(skill, contains('Flutter, bridge, Web, or browser'));
}
