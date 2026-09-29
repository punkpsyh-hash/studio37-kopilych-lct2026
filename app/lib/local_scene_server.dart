import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

/// Serves only bundled scene resources to this WebView, including when offline.
class LocalSceneServer {
  LocalSceneServer({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  HttpServer? _server;
  final _token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  Uri get index => Uri.parse(
    'http://127.0.0.1:${_server!.port}/$_token/assets/game3d/index.html',
  );

  bool owns(Uri url) =>
      _server != null &&
      url.scheme == 'http' &&
      url.host == '127.0.0.1' &&
      url.port == _server!.port &&
      url.path.startsWith('/$_token/assets/');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => unawaited(_serve(request)));
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Referrer-Policy', 'no-referrer');
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length < 4 ||
          segments.first != _token ||
          segments[1] != 'assets' ||
          !{'audio', 'game3d', 'models', 'fonts'}.contains(segments[2]) ||
          segments.any(
            (part) =>
                part.isEmpty ||
                part == '.' ||
                part == '..' ||
                part.contains('/') ||
                part.contains('\\'),
          )) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final path = segments.skip(1).join('/');
      final bytes = await _bundle.load(path);
      final extension = path.split('.').last.toLowerCase();
      final mime = switch (extension) {
        'html' => 'text/html; charset=utf-8',
        'js' || 'mjs' => 'text/javascript; charset=utf-8',
        'json' => 'application/json; charset=utf-8',
        'css' => 'text/css; charset=utf-8',
        'glb' => 'model/gltf-binary',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'ogg' => 'audio/ogg',
        'ttf' => 'font/ttf',
        _ => 'application/octet-stream',
      };
      response.headers.set(HttpHeaders.contentTypeHeader, mime);
      // Bundled assets never change within a session and every URL carries a
      // fresh per-session token, so the WebView may keep them instead of
      // re-reading tens of megabytes of GLB on each room change.
      response.headers.set(
        HttpHeaders.cacheControlHeader,
        extension == 'html' ? 'no-store' : 'private, max-age=86400, immutable',
      );
      if (extension == 'html') {
        response.headers.set(
          'Content-Security-Policy',
          "default-src 'self'; script-src 'self' 'unsafe-inline'; "
              "style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; "
              "connect-src 'self' blob:; worker-src 'self' blob:; frame-src 'none'",
        );
      }
      response.contentLength = bytes.lengthInBytes;
      if (request.method == 'GET') {
        response.add(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
