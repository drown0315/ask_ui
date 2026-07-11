part of 'launch_command.dart';

class _LaunchOutput {
  _LaunchOutput._();

  static LaunchCommandResult ready({
    required _LaunchOptions options,
    required _LaunchDevice selectedDevice,
    required LaunchAppResult appResult,
    required LaunchBridgeSession bridgeSession,
    required String projectRoot,
    required Uri workbenchUrl,
    required bool browserOpened,
    required String? browserOpenError,
  }) {
    final String agentCommand = _commandString([
      'ask_ui_bridge',
      'agent',
      'poll',
      '--base-url',
      bridgeSession.bridgeUrl.toString(),
      '--session-id',
      bridgeSession.sessionId,
    ]);
    return LaunchCommandResult(
      exitCode: 0,
      stdout: jsonEncode({
        'status': 'ready',
        'selectedDevice': selectedDevice.toJson(),
        'launchIntent': options.toJson(),
        'bridgeUrl': bridgeSession.bridgeUrl.toString(),
        'sessionId': bridgeSession.sessionId,
        'vmServiceUri': appResult.vmServiceUri,
        'projectRoot': projectRoot,
        'flavor': options.flavor,
        'target': options.target,
        'agentCommand': agentCommand,
        'workbenchUrl': workbenchUrl.toString(),
        'browserOpened': browserOpened,
        if (browserOpenError != null) 'browserOpenError': browserOpenError,
        'nextStep': 'Run the returned agent poll command.',
      }),
    );
  }

  static LaunchCommandResult needsDeviceSelection(
    _LaunchOptions options,
    List<_LaunchDevice> devices,
  ) {
    return LaunchCommandResult(
      exitCode: 0,
      stdout: jsonEncode({
        'status': 'needs_device_selection',
        'devices': devices
            .map((device) => {
                  ...device.toJson(),
                  'suggestedCommand': _commandString(
                    options.rerunArguments(device.id),
                  ),
                })
            .toList(growable: false),
        'launchIntent': options.toJson(),
        'nextStep':
            'Ask the user to choose a device, then rerun launch with --device.',
      }),
    );
  }

  static LaunchCommandResult failure(String code) {
    return LaunchCommandResult(
      exitCode: 1,
      stderr: jsonEncode({
        'status': 'error',
        'error': code,
      }),
    );
  }
}

String _commandString(List<String> arguments) {
  return arguments.map(_shellQuote).join(' ');
}

String _shellQuote(String argument) {
  if (RegExp(r'^[A-Za-z0-9_./:=@+-]+$').hasMatch(argument)) {
    return argument;
  }

  return "'${argument.replaceAll("'", r"'\''")}'";
}
