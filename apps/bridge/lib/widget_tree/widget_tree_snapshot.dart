/// One normalized Flutter Widget Tree node returned to the Ask UI web page.
///
/// It contains:
/// - `id`, copied from Flutter Inspector `valueId`
/// - `label`, copied from Flutter Inspector `description`
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
  });

  /// Convert one Flutter Inspector Diagnostics node into an Ask UI tree node.
  ///
  /// This method:
  /// 1. reads Flutter Inspector `valueId` as the stable node id for this
  ///    snapshot
  /// 2. reads `description` as the display label shown in the web tree
  /// 3. recursively converts `children`, defaulting missing children to an
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
    Map<String, Object?> diagnosticsNode,
  ) {
    final rawChildren = diagnosticsNode['children'];
    final children = rawChildren is List
        ? rawChildren
            .whereType<Map<String, Object?>>()
            .map(WidgetTreeNode.fromFlutterDiagnostics)
            .toList()
        : <WidgetTreeNode>[];

    return WidgetTreeNode(
      id: diagnosticsNode['valueId']?.toString() ?? '',
      label: diagnosticsNode['description']?.toString() ?? '',
      children: children,
    );
  }

  final String id;
  final String label;
  final List<WidgetTreeNode> children;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'children': children.map((child) => child.toJson()).toList(),
    };
  }
}
