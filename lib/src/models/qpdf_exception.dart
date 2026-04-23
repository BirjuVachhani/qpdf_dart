/// Error codes from the qpdf C library.
enum QpdfErrorCode {
  success,
  internal,
  system,
  unsupported,
  password,
  damagedPdf,
  pages,
  object,
  json,
  linearization,
}

/// Base exception for all qpdf errors.
sealed class QpdfException implements Exception {
  final String message;
  final QpdfErrorCode code;
  final String? filename;
  final int filePosition;
  final String? detail;

  const QpdfException(
    this.message, {
    required this.code,
    this.filename,
    this.filePosition = 0,
    this.detail,
  });

  @override
  String toString() => 'QpdfException($code): $message';
}

/// Incorrect password for an encrypted PDF.
final class QpdfPasswordException extends QpdfException {
  const QpdfPasswordException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.password);
}

/// Syntax errors or other damage in a PDF file.
final class QpdfDamagedPdfException extends QpdfException {
  const QpdfDamagedPdfException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.damagedPdf);
}

/// I/O or system-level error (file not found, memory, etc).
final class QpdfSystemException extends QpdfException {
  const QpdfSystemException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.system);
}

/// PDF feature not supported by qpdf.
final class QpdfUnsupportedException extends QpdfException {
  const QpdfUnsupportedException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.unsupported);
}

/// Erroneous or unsupported pages structure.
final class QpdfPagesException extends QpdfException {
  const QpdfPagesException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.pages);
}

/// Type/bounds error accessing objects.
final class QpdfObjectException extends QpdfException {
  const QpdfObjectException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.object);
}

/// Error in qpdf JSON processing.
final class QpdfJsonException extends QpdfException {
  const QpdfJsonException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.json);
}

/// Linearization error or warning.
final class QpdfLinearizationException extends QpdfException {
  const QpdfLinearizationException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.linearization);
}

/// Internal logic/programming error in qpdf.
final class QpdfInternalException extends QpdfException {
  const QpdfInternalException(
    super.message, {
    super.filename,
    super.filePosition,
    super.detail,
  }) : super(code: QpdfErrorCode.internal);
}

/// A non-fatal warning from qpdf.
final class QpdfWarning {
  final String message;
  final QpdfErrorCode code;
  final String? filename;
  final int filePosition;

  const QpdfWarning({
    required this.message,
    required this.code,
    this.filename,
    this.filePosition = 0,
  });

  @override
  String toString() => 'QpdfWarning($code): $message';
}
