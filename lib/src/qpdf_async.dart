import 'dart:isolate';
import 'dart:typed_data';

import 'models/encryption_params.dart';
import 'models/permissions.dart';
import 'models/qpdf_exception.dart';
import 'models/write_options.dart';
import 'qpdf_document.dart';

/// Async wrapper around [QpdfDocument] that runs operations in isolates.
///
/// Each method spawns a fresh isolate via [Isolate.run], performs the
/// operation, and returns the result. This is safe for use from Flutter
/// UI isolates and server event loops.
///
/// ```dart
/// final qpdf = QpdfAsync();
/// final info = await qpdf.getInfo('document.pdf');
/// print('Pages: ${info.pageCount}');
/// ```
final class QpdfAsync {
  const QpdfAsync();

  /// Returns document information without modifying the file.
  Future<PdfInfo> getInfo(String path, {String? password}) =>
      Isolate.run(() {
        final doc = QpdfDocument.open(path, password: password);
        try {
          return PdfInfo(
            pdfVersion: doc.pdfVersion,
            extensionLevel: doc.extensionLevel,
            pageCount: doc.pageCount,
            isLinearized: doc.isLinearized,
            isEncrypted: doc.isEncrypted,
            title: doc.title,
            author: doc.author,
            subject: doc.subject,
            keywords: doc.keywords,
            creator: doc.creator,
            producer: doc.producer,
            permissions: doc.permissions,
          );
        } finally {
          doc.dispose();
        }
      });

  /// Validates PDF structure. Returns warnings found.
  Future<List<QpdfWarning>> check(String path, {String? password}) =>
      Isolate.run(() {
        final doc = QpdfDocument.open(path, password: password);
        try {
          return doc.check();
        } finally {
          doc.dispose();
        }
      });

  /// Writes a PDF with the given options (encrypt, linearize, etc).
  Future<void> writeToFile(
    String inputPath,
    String outputPath, {
    String? password,
    WriteOptions options = const WriteOptions(),
  }) => Isolate.run(() {
    final doc = QpdfDocument.open(inputPath, password: password);
    try {
      doc.writeToFile(outputPath, options: options);
    } finally {
      doc.dispose();
    }
  });

  /// Reads a PDF and returns its bytes with the given options applied.
  Future<Uint8List> writeToBytes(
    String inputPath, {
    String? password,
    WriteOptions options = const WriteOptions(),
  }) => Isolate.run(() {
    final doc = QpdfDocument.open(inputPath, password: password);
    try {
      return doc.writeToBytes(options: options);
    } finally {
      doc.dispose();
    }
  });

  /// Encrypts a PDF file.
  Future<void> encrypt(
    String inputPath,
    String outputPath,
    EncryptionParams encryption, {
    String? password,
  }) => writeToFile(
    inputPath, outputPath,
    password: password,
    options: WriteOptions(
      preserveEncryption: false,
      encryption: encryption,
    ),
  );

  /// Decrypts a PDF file.
  Future<void> decrypt(
    String inputPath,
    String outputPath, {
    required String password,
  }) => writeToFile(
    inputPath, outputPath,
    password: password,
    options: const WriteOptions(preserveEncryption: false),
  );

  /// Linearizes (web-optimizes) a PDF file.
  Future<void> linearize(
    String inputPath,
    String outputPath, {
    String? password,
  }) => writeToFile(
    inputPath, outputPath,
    password: password,
    options: const WriteOptions(linearize: true),
  );

  /// Merges multiple PDF files into one.
  Future<void> merge(
    List<String> inputPaths,
    String outputPath, {
    WriteOptions options = const WriteOptions(),
  }) => Isolate.run(() {
    if (inputPaths.isEmpty) {
      throw ArgumentError('At least one input file is required');
    }

    final dest = QpdfDocument.open(inputPaths.first);
    try {
      for (var i = 1; i < inputPaths.length; i++) {
        final source = QpdfDocument.open(inputPaths[i]);
        try {
          for (final page in source.pages) {
            dest.addPage(source, page);
          }
        } finally {
          source.dispose();
        }
      }
      dest.writeToFile(outputPath, options: options);
    } finally {
      dest.dispose();
    }
  });

  /// Splits a PDF into individual page files.
  ///
  /// Output files are named `{outputPrefix}001.pdf`, `{outputPrefix}002.pdf`, etc.
  Future<void> splitPages(
    String inputPath,
    String outputPrefix, {
    String? password,
  }) => Isolate.run(() {
    final source = QpdfDocument.open(inputPath, password: password);
    try {
      final numPages = source.pageCount;
      for (var i = 0; i < numPages; i++) {
        final dest = QpdfDocument.empty();
        try {
          final page = source.getPage(i);
          dest.addPage(source, page);
          final pageNum = (i + 1).toString().padLeft(3, '0');
          dest.writeToFile('$outputPrefix$pageNum.pdf');
        } finally {
          dest.dispose();
        }
      }
    } finally {
      source.dispose();
    }
  });
}

/// Serializable document information returned by [QpdfAsync.getInfo].
final class PdfInfo {
  final String pdfVersion;
  final int extensionLevel;
  final int pageCount;
  final bool isLinearized;
  final bool isEncrypted;
  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final String? creator;
  final String? producer;
  final PdfPermissions permissions;

  const PdfInfo({
    required this.pdfVersion,
    required this.extensionLevel,
    required this.pageCount,
    required this.isLinearized,
    required this.isEncrypted,
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
    this.producer,
    required this.permissions,
  });

  @override
  String toString() => 'PdfInfo(v$pdfVersion, $pageCount pages'
      '${isEncrypted ? ", encrypted" : ""}'
      '${isLinearized ? ", linearized" : ""})';
}
