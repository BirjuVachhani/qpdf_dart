/// Dart FFI wrapper for the qpdf C library.
///
/// Provides PDF manipulation including encryption, decryption, linearization,
/// page management, and low-level PDF object access.
library;

// High-level API
export 'src/qpdf_async.dart';
export 'src/qpdf_document.dart';
export 'src/qpdf_object.dart';
export 'src/qpdf_page.dart';

// Domain models
export 'src/models/encryption_params.dart';
export 'src/models/enums.dart';
export 'src/models/permissions.dart';
export 'src/models/qpdf_exception.dart';
export 'src/models/write_options.dart';
