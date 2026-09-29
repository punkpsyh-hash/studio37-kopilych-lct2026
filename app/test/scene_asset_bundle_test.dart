import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kopilych/local_scene_server.dart';

class _OfflineAssetBinding extends AutomatedTestWidgetsFlutterBinding {
  // This test exercises the real loopback server, not a mocked HTTP response.
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _OfflineAssetBinding();

  test(
    'Every runtime room prop is bundled and served offline as GLB',
    () async {
      final descriptor =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/game3d/rooms/descriptor.json',
                ),
              )
              as Map<String, dynamic>;
      final paths = <String>{
        // Loaded directly by runtime-lighting.mjs when the fixture is absent.
        'assets/game3d/props/bathroom-pendant.glb',
      };
      for (final room in descriptor['rooms'] as List<dynamic>) {
        for (final group in ['jobProps', 'optionalFixtures']) {
          for (final prop in room[group] as List<dynamic>? ?? []) {
            paths.add('assets/game3d/props/${prop['file']}');
          }
        }
      }
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), containsAll(paths));

      final server = LocalSceneServer();
      final client = HttpClient();
      await server.start();
      try {
        for (final path in paths) {
          final response = await (await client.getUrl(
            server.index.resolve(path.substring('assets/game3d/'.length)),
          )).close();
          expect(response.statusCode, HttpStatus.ok, reason: path);
          expect(
            response.headers.contentType?.mimeType,
            'model/gltf-binary',
            reason: path,
          );
          final bytes = await response.fold<List<int>>(
            [],
            (result, chunk) => result..addAll(chunk),
          );
          expect(bytes.length, greaterThan(12), reason: path);
          expect(bytes.take(4), [0x67, 0x6c, 0x54, 0x46], reason: path);
          expect(response.contentLength, bytes.length, reason: path);
        }
      } finally {
        client.close(force: true);
        await server.close();
      }
    },
  );
}
