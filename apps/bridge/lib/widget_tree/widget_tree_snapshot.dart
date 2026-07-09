/// One normalized Flutter Widget Tree node returned to the Ask UI web page.
///
/// It contains:
/// - `id`, copied from Flutter Inspector `valueId`
/// - `label`, copied from Flutter Inspector `description`
/// - optional Selection Chat context such as source location and visible text
/// - `children`, always present even when the node has no children
///
/// Example:
/// A Flutter Inspector node with `valueId=inspector-1`, description `MaterialApp`,
/// and no children becomes `{id: inspector-1, label: MaterialApp, children: []}`.
class WidgetTreeNode {
  const WidgetTreeNode({
    required this.id,
    required this.label,
    required this.children,
    this.bounds,
    this.sourceLocation,
    this.visibleText,
    this.semanticInfo,
  });

  /// Convert one Flutter Inspector Diagnostics node into an Ask UI tree node.
  ///
  /// This method:
  /// 1. reads Flutter Inspector `valueId` as the stable node id for this
  ///    snapshot
  /// 2. reads `description` as the display label shown in the web tree
  /// 3. normalizes optional source location and preview context for Chat
  /// 4. recursively converts `children`, defaulting missing children to an
  ///    empty list
  ///
  /// Args:
  /// - `diagnosticsNode`: One decoded Flutter Inspector Diagnostics JSON object
  ///   from `ext.flutter.inspector.getRootWidgetTree`.
  ///
  /// Returns:
  /// A normalized `WidgetTreeNode` with `children` always present.
  ///
  /// Example:
  /// `{valueId: inspector-1, description: MaterialApp}` becomes
  /// `{id: inspector-1, label: MaterialApp, children: []}`.
  factory WidgetTreeNode.fromFlutterDiagnostics(
    Map<String, Object?> diagnosticsNode, {
    String? projectRoot,
    Map<String, WidgetBounds> boundsById = const {},
  }) {
    final rawChildren = diagnosticsNode['children'];
    final id = diagnosticsNode['valueId']?.toString() ?? '';
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map<String, Object?>>()
            .map(
              (child) => WidgetTreeNode.fromFlutterDiagnostics(
                child,
                projectRoot: projectRoot,
                boundsById: boundsById,
              ),
            )
            .toList()
        : <WidgetTreeNode>[];
    final description = diagnosticsNode['description']?.toString() ?? '';

    return WidgetTreeNode(
      id: id,
      label: description,
      sourceLocation: _sourceLocationFromDiagnostics(
        diagnosticsNode,
        projectRoot: projectRoot,
      ),
      visibleText: _visibleTextFromDiagnostics(diagnosticsNode, description),
      semanticInfo: _firstNonBlankString(diagnosticsNode, const [
        'semanticInfo',
        'semanticLabel',
        'semanticDescription',
      ]),
      bounds: boundsById[id],
      children: children,
    );
  }

  final String id;
  final String label;
  final WidgetBounds? bounds;
  final String? sourceLocation;
  final String? visibleText;
  final String? semanticInfo;
  final List<WidgetTreeNode> children;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      if (bounds != null) 'bounds': bounds!.toJson(),
      if (sourceLocation != null) 'sourceLocation': sourceLocation,
      if (visibleText != null) 'visibleText': visibleText,
      if (semanticInfo != null) 'semanticInfo': semanticInfo,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }
}

/// Visual rectangle for a Flutter widget in device-screen coordinates.
class WidgetBounds {
  const WidgetBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}

String? _sourceLocationFromDiagnostics(
  Map<String, Object?> diagnosticsNode, {
  required String? projectRoot,
}) {
  final sourceLocation = _stringFrom(diagnosticsNode['sourceLocation']);
  if (sourceLocation != null) {
    return _projectRelativeSourceLocation(sourceLocation, projectRoot);
  }

  final creationLocation = diagnosticsNode['creationLocation'];
  if (creationLocation is! Map<String, Object?>) {
    return null;
  }

  final rawFile = _stringFrom(creationLocation['file']);
  if (rawFile == null) {
    return null;
  }

  final file = _projectRelativeSourceLocation(
    _normalizeFileUri(rawFile),
    projectRoot,
  );
  final line = _positiveIntString(creationLocation['line']);
  final column = _positiveIntString(creationLocation['column']);

  return [
    file,
    if (line != null) line,
    if (column != null) column,
  ].join(':');
}

String? _visibleTextFromDiagnostics(
  Map<String, Object?> diagnosticsNode,
  String description,
) {
  return _firstNonBlankString(diagnosticsNode, const [
        'visibleText',
        'textPreview',
      ]) ??
      _textPreviewFromDescription(description);
}

String? _firstNonBlankString(
  Map<String, Object?> object,
  List<String> keys,
) {
  for (final key in keys) {
    final value = _stringFrom(object[key]);
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _stringFrom(Object? value) {
  if (value == null) {
    return null;
  }

  final stringValue = value.toString().trim();
  if (stringValue.isEmpty) {
    return null;
  }
  return stringValue;
}

String? _positiveIntString(Object? value) {
  final stringValue = _stringFrom(value);
  if (stringValue == null) {
    return null;
  }

  final intValue = int.tryParse(stringValue);
  if (intValue == null || intValue <= 0) {
    return null;
  }
  return intValue.toString();
}

String _normalizeFileUri(String file) {
  final uri = Uri.tryParse(file);
  if (uri != null && uri.scheme == 'file') {
    try {
      return uri.toFilePath();
    } on UnsupportedError {
      return uri.path;
    }
  }
  return file;
}

String _projectRelativeSourceLocation(
  String sourceLocation,
  String? projectRoot,
) {
  final trimmedSourceLocation = sourceLocation.trim();
  final trimmedProjectRoot = projectRoot?.trim().replaceAll(RegExp(r'/+$'), '');

  if (trimmedProjectRoot != null &&
      trimmedProjectRoot.isNotEmpty &&
      trimmedSourceLocation.startsWith('$trimmedProjectRoot/')) {
    return trimmedSourceLocation.substring(trimmedProjectRoot.length + 1);
  }

  return trimmedSourceLocation;
}

String? _textPreviewFromDescription(String description) {
  final match = RegExp(r"-\[<'([^']*)'>\]").firstMatch(description);
  final preview = match?.group(1)?.trim();
  if (preview == null || preview.isEmpty) {
    return null;
  }
  return preview;
}
