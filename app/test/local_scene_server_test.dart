import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/local_scene_server.dart';

class _SceneBundle extends CachingAssetBundle {
  final loaded = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (key == 'assets/game3d/index.html') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode('<html>local</html>')),
      );
    }
    if (key == 'assets/models/kitten-mobile.glb') {
      return ByteData.sublistView(Uint8List.fromList([0x67, 0x6c, 0x54, 0x46]));
    }
    if (key == 'assets/fonts/Nunito-800.ttf') {
      return ByteData.sublistView(Uint8List.fromList([0, 1, 0, 0]));
    }
    throw StateError('Missing asset');
  }
}

void main() {
  test(
    'Offline scene server serves bundled assets and denies other paths',
    () async {
      final bundle = _SceneBundle();
      final server = LocalSceneServer(bundle: bundle);
      final client = HttpClient();
      await server.start();
      try {
        final response = await (await client.getUrl(server.index)).close();
        expect(response.statusCode, 200);
        expect(await utf8.decoder.bind(response).join(), '<html>local</html>');
        expect(
          response.headers.value('Content-Security-Policy'),
          contains("connect-src 'self'"),
        );

        final modelUrl = server.index.resolve('../models/kitten-mobile.glb');
        final model = await (await client.getUrl(modelUrl)).close();
        expect(model.statusCode, 200);
        expect(await model.fold<List<int>>([], (a, b) => a..addAll(b)), [
          0x67,
          0x6c,
          0x54,
          0x46,
        ]);
        final font = await (await client.getUrl(
          server.index.resolve('../fonts/Nunito-800.ttf'),
        )).close();
        expect(font.statusCode, 200);
        expect(font.headers.contentType?.mimeType, 'font/ttf');
        expect(await font.fold<List<int>>([], (a, b) => a..addAll(b)), [
          0,
          1,
          0,
          0,
        ]);
        final served = bundle.loaded.length;
        for (final url in [
          server.index.replace(path: '/wrong/assets/game3d/index.html'),
          server.index.resolve('../voice/NOTICE.md'),
          server.index.resolve('../../state'),
        ]) {
          final denied = await (await client.getUrl(url)).close();
          expect(denied.statusCode, 404);
          await denied.drain<void>();
        }
        expect(bundle.loaded.length, served);
        final post = await (await client.postUrl(server.index)).close();
        expect(post.statusCode, 405);
        await post.drain<void>();
        expect(
          server.owns(
            Uri.parse('https://example.com/assets/game3d/index.html'),
          ),
          isFalse,
        );
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );
}
