import 'package:flutter_test/flutter_test.dart';
import 'package:ios_screen_mvp_flutter_demo/mvp_runtime_control.dart';

void main() {
  test('encodes Flutter logical view dimensions for the server', () {
    expect(
      encodeViewMetrics(
        physicalWidth: 750,
        physicalHeight: 1334,
        devicePixelRatio: 2,
      ),
      {
        'ok': true,
        'logicalWidth': 375.0,
        'logicalHeight': 667.0,
        'devicePixelRatio': 2.0,
      },
    );
  });
}
