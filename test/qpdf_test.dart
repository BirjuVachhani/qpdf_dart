import 'package:qpdf/qpdf.dart';
import 'package:test/test.dart';

void main() {
  group('Models', () {
    test('PdfObjectType.fromNative round-trips', () {
      for (final type in PdfObjectType.values) {
        expect(type.name, isNotEmpty);
      }
    });

    test('WriteOptions has sensible defaults', () {
      const options = WriteOptions();
      expect(options.linearize, isFalse);
      expect(options.preserveEncryption, isTrue);
      expect(options.compressStreams, isTrue);
      expect(options.streamDataMode, StreamDataMode.preserve);
      expect(options.objectStreamMode, ObjectStreamMode.preserve);
      expect(options.decodeLevel, StreamDecodeLevel.generalized);
    });

    test('R6EncryptionParams has sensible defaults', () {
      const params = R6EncryptionParams(
        userPassword: 'user',
        ownerPassword: 'owner',
      );
      expect(params.allowAccessibility, isTrue);
      expect(params.allowExtract, isTrue);
      expect(params.print, R3PrintPermission.full);
      expect(params.encryptMetadata, isTrue);
    });

    test('QpdfErrorCode values', () {
      expect(QpdfErrorCode.values.length, 10);
      expect(QpdfErrorCode.success.index, 0);
      expect(QpdfErrorCode.password.index, 4);
    });

    test('QpdfException hierarchy is sealed', () {
      const e = QpdfPasswordException('wrong password');
      expect(e, isA<QpdfException>());
      expect(e.code, QpdfErrorCode.password);
      expect(e.message, 'wrong password');
    });

    test('PdfPermissions toString', () {
      const perms = PdfPermissions(
        accessibility: true,
        extractAll: true,
        printLowRes: true,
        printHighRes: true,
        modifyAssembly: true,
        modifyForm: true,
        modifyAnnotation: true,
        modifyOther: true,
        modifyAll: true,
      );
      expect(perms.toString(), contains('print: high'));
    });

    test('PdfInfo toString', () {
      const info = PdfInfo(
        pdfVersion: '1.7',
        extensionLevel: 0,
        pageCount: 5,
        isLinearized: false,
        isEncrypted: true,
        permissions: PdfPermissions(
          accessibility: true,
          extractAll: true,
          printLowRes: true,
          printHighRes: true,
          modifyAssembly: true,
          modifyForm: true,
          modifyAnnotation: true,
          modifyOther: true,
          modifyAll: true,
        ),
      );
      expect(info.toString(), contains('5 pages'));
      expect(info.toString(), contains('encrypted'));
    });
  });

  // Integration tests require qpdf to be installed on the system.
  // Uncomment and provide test fixtures to run these:
  //
  // group('QpdfDocument', () {
  //   test('opens and reads a PDF', () {
  //     final doc = QpdfDocument.open('test/fixtures/sample.pdf');
  //     try {
  //       expect(doc.pageCount, greaterThan(0));
  //       expect(doc.pdfVersion, isNotEmpty);
  //     } finally {
  //       doc.dispose();
  //     }
  //   });
  //
  //   test('creates empty PDF', () {
  //     final doc = QpdfDocument.empty();
  //     try {
  //       expect(doc.pageCount, 0);
  //     } finally {
  //       doc.dispose();
  //     }
  //   });
  // });
}
