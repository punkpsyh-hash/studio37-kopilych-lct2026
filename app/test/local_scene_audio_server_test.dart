import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/local_scene_server.dart';

class _AudioBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'assets/audio/free-2026-09-26/ui_tap.ogg') {
      return ByteData.sublistView(Uint8List.fromList([0x4f, 0x67, 0x67, 0x53]));
    }
    throw StateError('Missing asset');
  }
}

void main() {
  test('Offline scene server serves only bundled OGG audio', () async {
    final server = LocalSceneServer(bundle: _AudioBundle());
    final client = HttpClient();
    await server.start();
    try {
      final url = server.index.resolve('../audio/free-2026-09-26/ui_tap.ogg');
      final response = await (await client.getUrl(url)).close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'audio/ogg');
      expect(await response.fold<List<int>>([], (all, bytes) => all..addAll(bytes)), [
        0x4f,
        0x67,
        0x67,
        0x53,
      ]);

      final denied = await (await client.getUrl(
        server.index.resolve('../audio/../voice/NOTICE.md'),
      )).close();
      expect(denied.statusCode, 404);
      await denied.drain<void>();
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}
