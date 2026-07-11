import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../app_controller/flutter_app_controller.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import '../server/ask_ui_bridge_server.dart';
import '../sessions/session_store.dart';

part 'launch_adapters.dart';
part 'launch_contracts.dart';
part 'launch_devices.dart';
part 'launch_options.dart';
part 'launch_output.dart';
part 'launch_web_dev.dart';
part 'launch_workbench_url.dart';

/// Runs the Ask UI launch command and returns machine-readable JSON.
///
/// The command selects a usable Flutter device, starts the app, creates a
/// Bridge Session, builds the packaged or Web dev workbench attach URL, and
/// opens it unless `--no-open` is present.
Future<LaunchCommandResult> runLaunchCommand(
  List<String> args, {
  FlutterDevicesRunner listDevices = Process.run,
  LaunchAppLauncher? appLauncher,
  LaunchBridgeLauncher? bridgeLauncher,
  LaunchBrowserOpener? browserOpener,
  LaunchWebDevServer? webDevServer,
}) async {
  late final _LaunchOptions options;
  try {
    options = _LaunchOptions.parse(args);
  } on _LaunchValidationError {
    return _LaunchOutput.failure('invalid_arguments');
  }

  late final List<_LaunchDevice> usableDevices;
  try {
    usableDevices = await _FlutterDeviceDiscovery(
      listDevices: listDevices,
    ).discoverUsableDevices();
  } on _DeviceDiscoveryException {
    return _LaunchOutput.failure('device_discovery_failed');
  }

  if (usableDevices.isEmpty) {
    return _LaunchOutput.failure('no_usable_devices');
  }

  final List<_LaunchDevice> matchingDevices = _matchingDevices(
    usableDevices,
    options.requestedDevice,
  );
  if (matchingDevices.length == 1) {
    return _launchSelectedDevice(
      options: options,
      selectedDevice: matchingDevices.single,
      appLauncher: appLauncher ?? const _FlutterRunAppLauncher(),
      bridgeLauncher: bridgeLauncher ?? LocalBridgeLauncher(),
      browserOpener: browserOpener ?? const _PlatformBrowserOpener(),
      webDevServer: webDevServer ?? NpmViteWebDevServer(),
    );
  }

  if (options.requestedDevice != null && matchingDevices.isEmpty) {
    return _LaunchOutput.failure('device_not_found');
  }

  if (usableDevices.length == 1 && options.requestedDevice == null) {
    return _launchSelectedDevice(
      options: options,
      selectedDevice: usableDevices.single,
      appLauncher: appLauncher ?? const _FlutterRunAppLauncher(),
      bridgeLauncher: bridgeLauncher ?? LocalBridgeLauncher(),
      browserOpener: browserOpener ?? const _PlatformBrowserOpener(),
      webDevServer: webDevServer ?? NpmViteWebDevServer(),
    );
  }

  return _LaunchOutput.needsDeviceSelection(
    options,
    matchingDevices.isEmpty ? usableDevices : matchingDevices,
  );
}

Future<LaunchCommandResult> _launchSelectedDevice({
  required _LaunchOptions options,
  required _LaunchDevice selectedDevice,
  required LaunchAppLauncher appLauncher,
  required LaunchBridgeLauncher bridgeLauncher,
  required LaunchBrowserOpener browserOpener,
  required LaunchWebDevServer webDevServer,
}) async {
  final String projectRoot =
      options.projectRoot ?? Directory.current.absolute.path;
  late final LaunchAppResult appResult;
  try {
    appResult = await appLauncher.launch(
      flutterRunArguments: options.flutterRunArguments(selectedDevice.id),
      projectRoot: projectRoot,
    );
  } on LaunchAppException catch (error) {
    return _LaunchOutput.failure(error.code);
  }

  late final LaunchBridgeSession bridgeSession;
  try {
    bridgeSession = await bridgeLauncher.createSession(
      vmServiceUri: appResult.vmServiceUri,
      projectRoot: projectRoot,
      deviceId: selectedDevice.id,
      requirePackagedWeb: !options.webDev,
    );
  } on LaunchBridgeException catch (error) {
    return _LaunchOutput.failure(error.code);
  }

  late final Uri workbenchBaseUrl;
  if (options.webDev) {
    try {
      workbenchBaseUrl = await webDevServer.start(projectRoot: projectRoot);
    } on LaunchWebDevException catch (error) {
      return _LaunchOutput.failure(error.code);
    }
  } else {
    workbenchBaseUrl = bridgeSession.bridgeUrl;
  }

  final Uri workbenchUrl = buildLaunchWorkbenchUrl(
    workbenchBaseUrl: workbenchBaseUrl,
    bridgeUrl: bridgeSession.bridgeUrl,
    sessionId: bridgeSession.sessionId,
    selectedDeviceId: selectedDevice.id,
    projectRoot: projectRoot,
    flavor: options.flavor,
    target: options.target,
  );
  bool browserOpened = false;
  String? browserOpenError;
  if (options.open) {
    try {
      await browserOpener.open(workbenchUrl);
      browserOpened = true;
    } on LaunchBrowserOpenException catch (error) {
      browserOpenError = error.code;
    } catch (_) {
      browserOpenError = 'browser_open_failed';
    }
  }

  return _LaunchOutput.ready(
    options: options,
    selectedDevice: selectedDevice,
    appResult: appResult,
    bridgeSession: bridgeSession,
    projectRoot: projectRoot,
    workbenchUrl: workbenchUrl,
    browserOpened: browserOpened,
    browserOpenError: browserOpenError,
  );
}
