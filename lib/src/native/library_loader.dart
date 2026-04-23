import 'dart:ffi';
import 'dart:io';

import '../bindings/qpdf_bindings.g.dart';

/// The loaded qpdf [DynamicLibrary] paired with its [QpdfBindings].
final class QpdfLibrary {
  final DynamicLibrary library;
  final QpdfBindings bindings;

  const QpdfLibrary(this.library, this.bindings);
}

/// Loads the native qpdf library for the current platform.
///
/// Resolution order:
/// 1. Native asset bundled by hook/build.dart (via asset URI)
/// 2. System-installed library (standard paths)
QpdfLibrary loadQpdfLibrary() {
  final lib = _openLibrary();
  return QpdfLibrary(lib, QpdfBindings(lib));
}

DynamicLibrary _openLibrary() {
  // Try loading by platform default name first (works for native assets and
  // system-installed libraries in library search path).
  try {
    return DynamicLibrary.open(_platformLibraryName());
  } on ArgumentError {
    // Fall through to explicit paths
  }

  // Try well-known system paths
  for (final path in _systemPaths()) {
    try {
      return DynamicLibrary.open(path);
    } on ArgumentError {
      continue;
    }
  }

  throw StateError(
    'Could not load qpdf native library. '
    'Ensure qpdf is installed on your system:\n'
    '  macOS:   brew install qpdf\n'
    '  Linux:   apt install libqpdf-dev\n'
    '  Windows: Download from https://github.com/qpdf/qpdf/releases',
  );
}

String _platformLibraryName() {
  if (Platform.isMacOS) return 'libqpdf.dylib';
  if (Platform.isLinux) return 'libqpdf.so';
  if (Platform.isWindows) return 'qpdf29.dll';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

List<String> _systemPaths() {
  if (Platform.isMacOS) {
    return [
      '/opt/homebrew/lib/libqpdf.dylib',
      '/usr/local/lib/libqpdf.dylib',
      '/opt/homebrew/lib/libqpdf.30.dylib',
      '/opt/homebrew/lib/libqpdf.29.dylib',
      '/usr/local/lib/libqpdf.30.dylib',
      '/usr/local/lib/libqpdf.29.dylib',
    ];
  }
  if (Platform.isLinux) {
    return [
      'libqpdf.so.29',
      '/usr/lib/x86_64-linux-gnu/libqpdf.so',
      '/usr/lib/aarch64-linux-gnu/libqpdf.so',
      '/usr/lib/libqpdf.so',
      '/usr/local/lib/libqpdf.so',
    ];
  }
  if (Platform.isWindows) {
    return [
      'qpdf29.dll',
      r'C:\Program Files\qpdf\bin\qpdf29.dll',
    ];
  }
  return [];
}
