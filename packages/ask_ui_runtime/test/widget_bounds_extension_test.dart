import 'package:ask_ui_runtime/src/ask_ui_runtime.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports not_element when Inspector id does not resolve to an Element',
      () {
    expect(widgetBoundsResultForInspectorObject(null), {
      'found': false,
      'reason': 'not_element',
    });
  });

  testWidgets('returns RenderBox global bounds in Flutter logical pixels',
      (tester) async {
    final key = GlobalKey();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 24,
              width: 80,
              height: 40,
              child: SizedBox(key: key),
            ),
          ],
        ),
      ),
    );

    final element = key.currentContext as Element;
    final result = widgetBoundsResultForInspectorObject(element);

    expect(result['found'], isTrue);
    expect(result['x'], 12.0);
    expect(result['y'], 24.0);
    expect(result['width'], 80.0);
    expect(result['height'], 40.0);
    expect(result['coordinateSpace'], 'flutterLogical');
    expect(result['devicePixelRatio'], tester.view.devicePixelRatio);
  });

}
