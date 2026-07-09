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

    test('normalizes optional widget context fields for Selection Chat', () {
      final root = WidgetTreeNode.fromFlutterDiagnostics(
        {
          'valueId': 'inspector-1',
          'description': 'FilledButton',
          'creationLocation': {
            'file': 'file:///Users/example/app/lib/home.dart',
            'line': 12,
            'column': 4,
          },
          'textPreview': 'Save',
          'semanticInfo': 'button',
          'children': [
            {
              'valueId': 'inspector-2',
              'description': "Text-[<'Save'>]",
              'creationLocation': {
                'file': '/Users/example/app/lib/home.dart',
                'line': 13,
              },
            },
          ],
        },
        projectRoot: '/Users/example/app',
      );

      expect(
        root.toJson(),
        {
          'id': 'inspector-1',
          'label': 'FilledButton',
          'sourceLocation': 'lib/home.dart:12:4',
          'visibleText': 'Save',
          'semanticInfo': 'button',
          'children': [
            {
              'id': 'inspector-2',
              'label': "Text-[<'Save'>]",
              'sourceLocation': 'lib/home.dart:13',
              'visibleText': 'Save',
              'children': <Object?>[],
            },
          ],
        },
      );
    });

    test('normalizes app-side visual bounds by widget id', () {
      final root = WidgetTreeNode.fromFlutterDiagnostics(
        {
          'valueId': 'inspector-1',
          'description': 'Text',
        },
        boundsById: const {
          'inspector-1': WidgetBounds(
            x: 10.5,
            y: 20,
            width: 100,
            height: 40,
          ),
        },
      );

      expect(
        root.toJson(),
        {
          'id': 'inspector-1',
          'label': 'Text',
          'bounds': {
            'x': 10.5,
            'y': 20.0,
            'width': 100.0,
            'height': 40.0,
          },
          'children': <Object?>[],
        },
      );
    });
  });
}
