import 'dart:ffi';

import '../bindings/qpdf_bindings.g.dart';
import '../models/qpdf_exception.dart';
import 'string_utils.dart';

/// Checks for errors after a qpdf C API call and throws if an error occurred.
///
/// Call this after any function that returns `QPDF_ERROR_CODE` or after
/// functions that don't return error codes but may set error state.
void checkError(QpdfBindings bindings, qpdf_data handle) {
  if (bindings.qpdf_has_error(handle) == QPDF_TRUE) {
    final error = bindings.qpdf_get_error(handle);
    if (error == nullptr) {
      throw const QpdfInternalException('Unknown error occurred');
    }
    _throwFromError(bindings, handle, error);
  }
}

/// Checks a return code and throws on error.
void checkErrorCode(QpdfBindings bindings, qpdf_data handle, int errorCode) {
  if (errorCode & QPDF_ERRORS != 0) {
    checkError(bindings, handle);
    // If checkError didn't throw (shouldn't happen), throw generic
    throw const QpdfInternalException('Operation failed with error code');
  }
}

/// Collects all pending warnings from the qpdf handle.
List<QpdfWarning> collectWarnings(QpdfBindings bindings, qpdf_data handle) {
  final warnings = <QpdfWarning>[];
  while (bindings.qpdf_more_warnings(handle) == QPDF_TRUE) {
    final warning = bindings.qpdf_next_warning(handle);
    if (warning != nullptr) {
      warnings.add(QpdfWarning(
        message: fromCString(bindings.qpdf_get_error_full_text(handle, warning)),
        code: _mapErrorCode(bindings.qpdf_get_error_code(handle, warning)),
        filename: fromCStringNullable(
          bindings.qpdf_get_error_filename(handle, warning),
        ),
        filePosition: bindings.qpdf_get_error_file_position(handle, warning),
      ));
    }
  }
  return warnings;
}

Never _throwFromError(
  QpdfBindings bindings,
  qpdf_data handle,
  qpdf_error error,
) {
  final fullText = fromCString(
    bindings.qpdf_get_error_full_text(handle, error),
  );
  final code = _mapErrorCode(bindings.qpdf_get_error_code(handle, error));
  final filename = fromCStringNullable(
    bindings.qpdf_get_error_filename(handle, error),
  );
  final filePosition = bindings.qpdf_get_error_file_position(handle, error);
  final detail = fromCStringNullable(
    bindings.qpdf_get_error_message_detail(handle, error),
  );

  throw switch (code) {
    QpdfErrorCode.password => QpdfPasswordException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.damagedPdf => QpdfDamagedPdfException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.system => QpdfSystemException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.unsupported => QpdfUnsupportedException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.pages => QpdfPagesException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.object => QpdfObjectException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.json => QpdfJsonException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.linearization => QpdfLinearizationException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
    QpdfErrorCode.internal || QpdfErrorCode.success => QpdfInternalException(
      fullText,
      filename: filename,
      filePosition: filePosition,
      detail: detail,
    ),
  };
}

QpdfErrorCode _mapErrorCode(qpdf_error_code_e code) {
  return switch (code) {
    qpdf_error_code_e.qpdf_e_success => QpdfErrorCode.success,
    qpdf_error_code_e.qpdf_e_internal => QpdfErrorCode.internal,
    qpdf_error_code_e.qpdf_e_system => QpdfErrorCode.system,
    qpdf_error_code_e.qpdf_e_unsupported => QpdfErrorCode.unsupported,
    qpdf_error_code_e.qpdf_e_password => QpdfErrorCode.password,
    qpdf_error_code_e.qpdf_e_damaged_pdf => QpdfErrorCode.damagedPdf,
    qpdf_error_code_e.qpdf_e_pages => QpdfErrorCode.pages,
    qpdf_error_code_e.qpdf_e_object => QpdfErrorCode.object,
    qpdf_error_code_e.qpdf_e_json => QpdfErrorCode.json,
    qpdf_error_code_e.qpdf_e_linearization => QpdfErrorCode.linearization,
  };
}
