import 'package:ask_ui_bridge/widget_tree/widget_tree_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('WidgetTreeNode', () {
    test('normalizes Flutter Diagnostics nodes into Ask UI widget tree nodes',
        () {
      final root = WidgetTreeNode.fromFlutterDiagnostics({
        'valueId': 'inspector-1',
        'description': 'MaterialApp',
        'children': [
          {
            'valueId': 'inspector-2',
            'description': 'Scaffold',
          },
        ],
      });

      expect(
        root.toJson(),
        {
          'id': 'inspector-1',
          'label': 'MaterialApp',
          'children': [
            {
              'id': 'inspector-2',
              'label': 'Scaffold',
              'children': <Object?>[],
            },
          ],
        },
      );
    });
  });
}
