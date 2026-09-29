# Vendored ONNX Runtime Flutter FFI plugin

Source: `onnxruntime` 1.4.1 by gtbluesky, https://pub.dev/packages/onnxruntime .
License: MIT; original license is in `LICENSE`.

Only the Dart bindings and Android Gradle plugin files are retained. The
plugin's own `libonnxruntime.so` was omitted to avoid two libraries with the
same name in the Android APK. The app uses the `libonnxruntime.so` already
packaged by `sherpa_onnx_android_arm64` 1.13.8. The FFI bindings request ONNX
Runtime C API version 14; the bundled runtime supports API version 17.

Any update to either package requires renewed arm64 build and device inference
tests before release. This vendor copy does not contain a native runtime.
