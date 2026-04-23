import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Converts a Dart [String] to a C string allocated with [allocator].
///
/// The caller is responsible for freeing the memory (use [Arena] for
/// automatic cleanup).
Pointer<Char> toCString(String value, Allocator allocator) {
  return value.toNativeUtf8(allocator: allocator).cast<Char>();
}

/// Converts a C string pointer to a Dart [String].
///
/// Returns an empty string if [ptr] is null.
String fromCString(Pointer<Char> ptr) {
  if (ptr == nullptr) return '';
  return ptr.cast<Utf8>().toDartString();
}

/// Converts a C string pointer to a nullable Dart [String].
///
/// Returns `null` if [ptr] is null.
String? fromCStringNullable(Pointer<Char> ptr) {
  if (ptr == nullptr) return null;
  return ptr.cast<Utf8>().toDartString();
}
