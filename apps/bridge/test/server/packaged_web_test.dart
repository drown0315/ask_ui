import 'dart:convert';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer packaged Web', () {
    test('serves packaged workbench index from root', () async {
      await FileTestkit.runZoned(() async {
        final fixture = await startFixture();
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(fixture.baseUri.resolve('/'));
        final response = await request.close();
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentType?.mimeType, 'text/html');
        expect(body, contains('Ask UI'));
      });
    });

    test('serves packaged JavaScript assets', () async {
      await FileTestkit.runZoned(() async {
        final fixture = await startFixture();
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(
          fixture.baseUri.resolve('/assets/app.js'),
        );
        final response = await request.close();
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, HttpStatus.ok);
        expect(
          response.headers.contentType?.mimeType,
          'application/javascript',
        );
        expect(body, 'console.log("ask ui");');
      });
    });

    test('keeps unknown API routes as JSON errors', () async {
      await FileTestkit.runZoned(() async {
        final fixture = await startFixture();
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(
          fixture.baseUri.resolve('/api/missing'),
        );
        final response = await request.close();
        final body = jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;

        expect(response.statusCode, HttpStatus.notFound);
        expect(response.headers.contentType?.mimeType, 'application/json');
        expect(body, {'error': 'not_found'});
      });
    });

    test('falls back to index for non-API workbench routes', () async {
      await FileTestkit.runZoned(() async {
        final fixture = await startFixture();
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(
          fixture.baseUri.resolve('/sessions/session-1/comments'),
        );
        final response = await request.close();
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers.contentType?.mimeType, 'text/html');
        expect(body, contains('Ask UI'));
      });
    });

    test('returns JSON not found for missing packaged assets', () async {
      await FileTestkit.runZoned(() async {
        final fixture = await startFixture();
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(
          fixture.baseUri.resolve('/assets/missing.js'),
        );
        final response = await request.close();
        final body = jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;

        expect(response.statusCode, HttpStatus.notFound);
        expect(response.headers.contentType?.mimeType, 'application/json');
        expect(body, {'error': 'packaged_web_asset_not_found'});
      });
    });

    test('returns JSON not found when packaged Web root is missing', () async {
      await FileTestkit.runZoned(() async {
        final packagedWebRoot = Directory('/ask-ui-packaged-web-test');
        final fixture = BridgeServerFixture();
        await fixture.start(packagedWebRoot: packagedWebRoot);
        addTearDown(fixture.close);
        final client = HttpClient();
        addTearDown(client.close);

        final request = await client.getUrl(fixture.baseUri.resolve('/'));
        final response = await request.close();
        final body = jsonDecode(await utf8.decodeStream(response))
            as Map<String, Object?>;

        expect(response.statusCode, HttpStatus.notFound);
        expect(response.headers.contentType?.mimeType, 'application/json');
        expect(body, {'error': 'packaged_web_not_found'});
      });
    });
  });
}

Future<BridgeServerFixture> startFixture() async {
  final packagedWebRoot = Directory('/ask-ui-packaged-web-test');
  await packagedWebRoot.create();
  await File('${packagedWebRoot.path}/index.html').writeAsString(
    '<!doctype html><div id="root">Ask UI</div>',
  );
  await Directory('${packagedWebRoot.path}/assets').create();
  await File('${packagedWebRoot.path}/assets/app.js').writeAsString(
    'console.log("ask ui");',
  );

  final fixture = BridgeServerFixture();
  await fixture.start(packagedWebRoot: packagedWebRoot);
  addTearDown(fixture.close);
  return fixture;
}
