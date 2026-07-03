class BridgeLogger {
  const BridgeLogger({
    required this.write,
  });

  final void Function(String message) write;

  void info(String message) {
    write('[ask_ui_bridge] $message');
  }
}
