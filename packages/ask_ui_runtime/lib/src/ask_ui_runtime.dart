import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

const _widgetBoundsExtensionName = 'ext.ask_ui.widgetBounds';

bool _didRegisterAskUiRuntime = false;

/// Registers Ask UI debug runtime service extensions for the current app.
///
/// Call this before `runApp` in a Flutter debug build:
///
/// ```dart
/// void main() {
///   registerAskUiRuntime();
///   runApp(const MyApp());
/// }
/// ```
///
/// The registration is wrapped in `assert`, so it is tree-shaken from release
/// builds and has no production behavior.
void registerAskUiRuntime() {
  assert(() {
    if (_didRegisterAskUiRuntime) {
      return true;
    }
    _didRegisterAskUiRuntime = true;
    developer.registerExtension(
      _widgetBoundsExtensionName,
      _handleWidgetBoundsExtension,
    );
    return true;
  }());
}

Future<developer.ServiceExtensionResponse> _handleWidgetBoundsExtension(
  String method,
  Map<String, String> parameters,
) async {
  final id = parameters['id'];
  final groupName = parameters['groupName'];
  final inspector = WidgetInspectorService.instance as dynamic;
  final object = inspector.toObject(id, groupName);

  return _jsonResult(widgetBoundsResultForInspectorObject(object));
}

developer.ServiceExtensionResponse _jsonResult(Map<String, Object?> result) {
  return developer.ServiceExtensionResponse.result(jsonEncode(result));
}

/// Converts a Flutter Inspector object into Ask UI widget bounds JSON.
///
/// This is public only for package tests. App code should call
/// [registerAskUiRuntime] instead.
Map<String, Object?> widgetBoundsResultForInspectorObject(Object? object) {
  if (object is! Element) {
    return {
      'found': false,
      'reason': 'not_element',
    };
  }

  final renderObject = object.renderObject;
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return {
      'found': false,
      'reason': 'not_render_box',
    };
  }

  final topLeft = renderObject.localToGlobal(Offset.zero);
  final view = View.maybeOf(object);
  final physicalSize = view?.physicalSize;

  return {
    'found': true,
    'x': topLeft.dx,
    'y': topLeft.dy,
    'width': renderObject.size.width,
    'height': renderObject.size.height,
    'coordinateSpace': 'flutterLogical',
    'devicePixelRatio': view?.devicePixelRatio ?? 1.0,
    if (physicalSize != null)
      'physicalSize': {
        'width': physicalSize.width,
        'height': physicalSize.height,
      },
  };
}
