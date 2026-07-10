part of 'launch_command.dart';

/// Build the workbench URL that attaches to an existing Bridge Session.
///
/// Packaged mode uses the Bridge Server as the workbench base URL. Web dev
/// mode uses the Vite URL while still pointing `bridgeUrl` at the Bridge Server.
Uri buildLaunchWorkbenchUrl({
  Uri? workbenchBaseUrl,
  required Uri bridgeUrl,
  required String sessionId,
  required String selectedDeviceId,
  required String projectRoot,
  required String? flavor,
  required String? target,
}) {
  final Map<String, String> queryParameters = <String, String>{
    'bridgeUrl': _withoutTrailingSlash(bridgeUrl.toString()),
    'sessionId': sessionId,
    'deviceId': selectedDeviceId,
    'projectRoot': projectRoot,
  };
  if (flavor != null) {
    queryParameters['flavor'] = flavor;
  }
  if (target != null) {
    queryParameters['target'] = target;
  }

  final Uri baseUrl = workbenchBaseUrl ?? bridgeUrl;
  return baseUrl.replace(
    path: '/',
    queryParameters: queryParameters,
  );
}

String _withoutTrailingSlash(String value) {
  return value.replaceFirst(RegExp(r'/+$'), '');
}
