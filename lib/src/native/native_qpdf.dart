import 'dart:ffi';

import '../bindings/qpdf_bindings.g.dart';
import 'library_loader.dart';
import 'string_utils.dart';

/// Provides singleton-per-isolate access to the qpdf native library.
///
/// Dart isolates do not share static state, so each isolate initializes its
/// own [DynamicLibrary] reference and [QpdfBindings] instance on first access.
abstract final class NativeQpdf {
  static QpdfLibrary? _library;

  static QpdfLibrary get _lib => _library ??= loadQpdfLibrary();

  /// The loaded qpdf bindings for the current isolate.
  static QpdfBindings get bindings => _lib.bindings;

  /// Returns the address of `qpdf_cleanup`, suitable for use as a
  /// [NativeFinalizer] callback.
  ///
  /// The function signature `void qpdf_cleanup(qpdf_data*)` matches
  /// [NativeFinalizerFunction] at the ABI level, so this can be used directly
  /// with [NativeFinalizer].
  static Pointer<NativeFinalizerFunction> get cleanupFinalizer =>
      _lib.library
          .lookup<NativeFunction<Void Function(Pointer<qpdf_data>)>>(
            'qpdf_cleanup',
          )
          .cast();

  /// The qpdf library version string.
  static String get version =>
      fromCString(bindings.qpdf_get_qpdf_version());
}
