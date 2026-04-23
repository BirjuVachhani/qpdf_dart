import 'package:qpdf/qpdf.dart';

/// Demonstrates sync and async usage of the qpdf package.
void main() async {
  // --- Sync API (blocks the calling thread) ---

  // Open a PDF file
  final doc = QpdfDocument.open('input.pdf');
  try {
    // Read document info
    print('PDF version: ${doc.pdfVersion}');
    print('Page count:  ${doc.pageCount}');
    print('Encrypted:   ${doc.isEncrypted}');
    print('Title:       ${doc.title}');

    // Modify metadata
    doc.title = 'Updated Title';
    doc.author = 'Dart qpdf';

    // Write with linearization
    doc.writeToFile('output.pdf', options: WriteOptions(linearize: true));

    // Encrypt with AES-256
    doc.writeToFile('encrypted.pdf', options: WriteOptions(
      preserveEncryption: false,
      encryption: R6EncryptionParams(
        userPassword: 'user123',
        ownerPassword: 'owner456',
        allowExtract: false,
        print: R3PrintPermission.low,
      ),
    ));

    // Access pages
    for (var i = 0; i < doc.pageCount; i++) {
      final page = doc.getPage(i);
      print('Page $i: objectId=${page.objectId}');
    }

    // Low-level object access
    final root = doc.root;
    print('Root type: ${root.typeName}');
    final pages = root.getKey('/Pages');
    print('Pages count key: ${pages.getKey('/Count').intValue}');
  } finally {
    doc.dispose();
  }

  // --- Async API (runs in isolates, safe for Flutter UI) ---

  const qpdf = QpdfAsync();

  // Get PDF info without blocking
  final info = await qpdf.getInfo('input.pdf');
  print('Async info: ${info.pageCount} pages, v${info.pdfVersion}');

  // Merge multiple PDFs
  await qpdf.merge(
    ['file1.pdf', 'file2.pdf', 'file3.pdf'],
    'merged.pdf',
  );

  // Encrypt asynchronously
  await qpdf.encrypt(
    'input.pdf',
    'encrypted_async.pdf',
    R6EncryptionParams(
      userPassword: 'secret',
      ownerPassword: 'owner',
    ),
  );

  // Linearize for web
  await qpdf.linearize('input.pdf', 'web_optimized.pdf');

  // Validate PDF
  final warnings = await qpdf.check('input.pdf');
  if (warnings.isEmpty) {
    print('PDF is valid!');
  } else {
    for (final w in warnings) {
      print('Warning: ${w.message}');
    }
  }
}
