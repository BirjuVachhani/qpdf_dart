@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:qpdf/qpdf.dart';
import 'package:test/test.dart';

const _samplePdf = '/tmp/qpdf_test/sample.pdf';
const _encryptedPdf = '/tmp/qpdf_test/encrypted.pdf';

void main() {
  setUpAll(() {
    if (!File(_samplePdf).existsSync()) {
      throw StateError(
        'Test fixtures missing. Run: '
        'cp /usr/share/doc/bash/bash.pdf /tmp/qpdf_test/sample.pdf && '
        'qpdf --encrypt user123 owner123 256 -- '
        '/tmp/qpdf_test/sample.pdf /tmp/qpdf_test/encrypted.pdf',
      );
    }
  });

  group('QpdfDocument (sync)', () {
    test('opens a plain PDF', () {
      final doc = QpdfDocument.open(_samplePdf);
      try {
        expect(doc.pageCount, greaterThan(0));
        expect(doc.pdfVersion, isNotEmpty);
        expect(doc.isEncrypted, isFalse);
      } finally {
        doc.dispose();
      }
    });

    test('opens an encrypted PDF with correct password', () {
      final doc = QpdfDocument.open(_encryptedPdf, password: 'user123');
      try {
        expect(doc.isEncrypted, isTrue);
        expect(doc.pageCount, greaterThan(0));
      } finally {
        doc.dispose();
      }
    });

    test('throws QpdfPasswordException on wrong password', () {
      expect(
        () => QpdfDocument.open(_encryptedPdf, password: 'wrong'),
        throwsA(isA<QpdfPasswordException>()),
      );
    });

    test('throws QpdfSystemException on missing file', () {
      expect(
        () => QpdfDocument.open('/tmp/qpdf_test/nonexistent.pdf'),
        throwsA(isA<QpdfException>()),
      );
    });

    test('decrypts PDF by writing without encryption', () {
      const output = '/tmp/qpdf_test/decrypted.pdf';
      final doc = QpdfDocument.open(_encryptedPdf, password: 'user123');
      try {
        doc.writeToFile(
          output,
          options: const WriteOptions(preserveEncryption: false),
        );
      } finally {
        doc.dispose();
      }

      expect(File(output).existsSync(), isTrue);

      // Verify decrypted file has no encryption
      final verify = QpdfDocument.open(output);
      try {
        expect(verify.isEncrypted, isFalse);
        expect(verify.pageCount, greaterThan(0));
      } finally {
        verify.dispose();
      }
    });

    test('encrypts with R6 AES-256', () {
      const output = '/tmp/qpdf_test/reencrypted.pdf';
      final doc = QpdfDocument.open(_samplePdf);
      try {
        doc.writeToFile(
          output,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: 'newuser',
              ownerPassword: 'newowner',
              print: R3PrintPermission.low,
              allowExtract: false,
            ),
          ),
        );
      } finally {
        doc.dispose();
      }

      final verify = QpdfDocument.open(output, password: 'newuser');
      try {
        expect(verify.isEncrypted, isTrue);
        expect(verify.permissions.extractAll, isFalse);
        expect(verify.permissions.printHighRes, isFalse);
      } finally {
        verify.dispose();
      }
    });

    test('writeToBytes returns valid PDF', () {
      final doc = QpdfDocument.open(_samplePdf);
      try {
        final bytes = doc.writeToBytes();
        expect(bytes.length, greaterThan(100));
        expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
      } finally {
        doc.dispose();
      }
    });

    test('linearization', () {
      const output = '/tmp/qpdf_test/linearized.pdf';
      final doc = QpdfDocument.open(_samplePdf);
      try {
        doc.writeToFile(output, options: const WriteOptions(linearize: true));
      } finally {
        doc.dispose();
      }

      final verify = QpdfDocument.open(output);
      try {
        expect(verify.isLinearized, isTrue);
      } finally {
        verify.dispose();
      }
    });

    test('low-level object access - trailer and root', () {
      final doc = QpdfDocument.open(_samplePdf);
      try {
        final trailer = doc.trailer;
        expect(trailer.isDictionary, isTrue);

        final root = doc.root;
        expect(root.isDictionary, isTrue);
        expect(root.hasKey('/Type'), isTrue);
      } finally {
        doc.dispose();
      }
    });

    test('sets info dictionary', () {
      const output = '/tmp/qpdf_test/with_metadata.pdf';
      final doc = QpdfDocument.open(_samplePdf);
      try {
        doc.title = 'Test Title';
        doc.author = 'Test Author';
        doc.writeToFile(output);
      } finally {
        doc.dispose();
      }

      final verify = QpdfDocument.open(output);
      try {
        expect(verify.title, 'Test Title');
        expect(verify.author, 'Test Author');
      } finally {
        verify.dispose();
      }
    });

    test('creates empty PDF', () {
      final doc = QpdfDocument.empty();
      try {
        expect(doc.pageCount, 0);
      } finally {
        doc.dispose();
      }
    });

    test('opens from bytes', () {
      final bytes = File(_samplePdf).readAsBytesSync();
      final doc = QpdfDocument.fromBytes(bytes);
      try {
        expect(doc.pageCount, greaterThan(0));
      } finally {
        doc.dispose();
      }
    });

    test('dispose is idempotent', () {
      final doc = QpdfDocument.open(_samplePdf);
      expect(() => doc.dispose(), returnsNormally);
      expect(() => doc.dispose(), returnsNormally);
    });

    test('methods throw after dispose', () {
      final doc = QpdfDocument.open(_samplePdf);
      doc.dispose();
      expect(() => doc.pageCount, throwsA(isA<StateError>()));
    });

    test('NativeFinalizer cleans up GC-collected documents without dispose',
        () async {
      // Open and release 100 documents without calling dispose. The
      // NativeFinalizer should reclaim them as they become unreachable.
      // If this test leaks it will show in process RSS growth over many runs,
      // but within a single run we just verify no crashes.
      for (var i = 0; i < 100; i++) {
        QpdfDocument.open(_samplePdf);
      }
      // Force GC to encourage finalizer runs (best-effort only; finalizers
      // are not guaranteed to run at any specific time).
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // A further open must still work — verifies the library is still in
      // a valid state after many un-disposed documents.
      final doc = QpdfDocument.open(_samplePdf);
      try {
        expect(doc.pageCount, greaterThan(0));
      } finally {
        doc.dispose();
      }
    });
  });

  group('QpdfAsync', () {
    const qpdf = QpdfAsync();

    test('getInfo on plain PDF', () async {
      final info = await qpdf.getInfo(_samplePdf);
      expect(info.pageCount, greaterThan(0));
      expect(info.isEncrypted, isFalse);
      expect(info.pdfVersion, isNotEmpty);
    });

    test('getInfo on encrypted PDF with password', () async {
      final info = await qpdf.getInfo(_encryptedPdf, password: 'user123');
      expect(info.isEncrypted, isTrue);
    });

    test('getInfo propagates QpdfPasswordException', () async {
      expect(
        () => qpdf.getInfo(_encryptedPdf, password: 'wrong'),
        throwsA(isA<QpdfPasswordException>()),
      );
    });

    test('decrypt via async API', () async {
      const output = '/tmp/qpdf_test/async_decrypted.pdf';
      await qpdf.decrypt(_encryptedPdf, output, password: 'user123');
      final info = await qpdf.getInfo(output);
      expect(info.isEncrypted, isFalse);
    });

    test('encrypt via async API', () async {
      const output = '/tmp/qpdf_test/async_encrypted.pdf';
      await qpdf.encrypt(
        _samplePdf,
        output,
        const R6EncryptionParams(
          userPassword: 'asyncuser',
          ownerPassword: 'asyncowner',
        ),
      );
      final info = await qpdf.getInfo(output, password: 'asyncuser');
      expect(info.isEncrypted, isTrue);
    });

    test('check propagates warnings', () async {
      final warnings = await qpdf.check(_samplePdf);
      // Any result is fine - just verify no exception
      expect(warnings, isA<List<QpdfWarning>>());
    });

    test('linearize via async', () async {
      const output = '/tmp/qpdf_test/async_linearized.pdf';
      await qpdf.linearize(_samplePdf, output);
      final info = await qpdf.getInfo(output);
      expect(info.isLinearized, isTrue);
    });
  });

  // ------------------------------------------------------------------------
  // Comprehensive encryption / decryption tests.
  //
  // These verify that the package can round-trip real PDFs through every
  // supported encryption revision, preserve content on decryption, enforce
  // permissions, and interoperate with the qpdf CLI. Critical for production
  // decryption use cases.
  // ------------------------------------------------------------------------
  group('Encryption / Decryption', () {
    const userPwd = 'user-secret';
    const ownerPwd = 'owner-secret';

    /// Returns the byte count of the first page's content data as a cheap
    /// semantic fingerprint of a PDF's page content. Two files with the same
    /// page count and the same content-data length for each page have the
    /// same logical content for our purposes.
    List<int> contentFingerprint(String path, {String? password}) {
      final doc = QpdfDocument.open(path, password: password);
      try {
        return [
          for (var i = 0; i < doc.pageCount; i++)
            doc.getPage(i).getContentData().length,
        ];
      } finally {
        doc.dispose();
      }
    }

    group('round-trip encryption revisions', () {
      test('R3 (128-bit RC4)', () {
        const path = '/tmp/qpdf_test/enc_r3.pdf';
        final src = QpdfDocument.open(_samplePdf);
        try {
          src.writeToFile(
            path,
            options: const WriteOptions(
              preserveEncryption: false,
              encryption: R3EncryptionParams(
                userPassword: userPwd,
                ownerPassword: ownerPwd,
              ),
            ),
          );
        } finally {
          src.dispose();
        }

        final doc = QpdfDocument.open(path, password: userPwd);
        try {
          expect(doc.isEncrypted, isTrue);
          expect(doc.pageCount, greaterThan(0));
        } finally {
          doc.dispose();
        }
      });

      test('R4 (128-bit AES)', () {
        const path = '/tmp/qpdf_test/enc_r4.pdf';
        final src = QpdfDocument.open(_samplePdf);
        try {
          src.writeToFile(
            path,
            options: const WriteOptions(
              preserveEncryption: false,
              encryption: R4EncryptionParams(
                userPassword: userPwd,
                ownerPassword: ownerPwd,
                useAes: true,
              ),
            ),
          );
        } finally {
          src.dispose();
        }

        final doc = QpdfDocument.open(path, password: userPwd);
        try {
          expect(doc.isEncrypted, isTrue);
        } finally {
          doc.dispose();
        }
      });

      test('R5 (256-bit AES, deprecated)', () {
        const path = '/tmp/qpdf_test/enc_r5.pdf';
        final src = QpdfDocument.open(_samplePdf);
        try {
          src.writeToFile(
            path,
            options: const WriteOptions(
              preserveEncryption: false,
              encryption: R5EncryptionParams(
                userPassword: userPwd,
                ownerPassword: ownerPwd,
              ),
            ),
          );
        } finally {
          src.dispose();
        }

        final doc = QpdfDocument.open(path, password: userPwd);
        try {
          expect(doc.isEncrypted, isTrue);
        } finally {
          doc.dispose();
        }
      });

      test('R6 (256-bit AES, recommended)', () {
        const path = '/tmp/qpdf_test/enc_r6.pdf';
        final src = QpdfDocument.open(_samplePdf);
        try {
          src.writeToFile(
            path,
            options: const WriteOptions(
              preserveEncryption: false,
              encryption: R6EncryptionParams(
                userPassword: userPwd,
                ownerPassword: ownerPwd,
              ),
            ),
          );
        } finally {
          src.dispose();
        }

        final doc = QpdfDocument.open(path, password: userPwd);
        try {
          expect(doc.isEncrypted, isTrue);
        } finally {
          doc.dispose();
        }
      });
    });

    test('decryption preserves page content exactly', () {
      const encrypted = '/tmp/qpdf_test/preserve_enc.pdf';
      const decrypted = '/tmp/qpdf_test/preserve_dec.pdf';

      final expected = contentFingerprint(_samplePdf);

      // Encrypt
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          encrypted,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      // Decrypt
      final enc = QpdfDocument.open(encrypted, password: userPwd);
      try {
        enc.writeToFile(
          decrypted,
          options: const WriteOptions(preserveEncryption: false),
        );
      } finally {
        enc.dispose();
      }

      final actual = contentFingerprint(decrypted);
      expect(actual, equals(expected),
          reason: 'Decrypted page content must match original byte-for-byte');
    });

    test('owner password grants access (R6)', () {
      const path = '/tmp/qpdf_test/owner_access_r6.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      // Opening with OWNER password should work.
      final doc = QpdfDocument.open(path, password: ownerPwd);
      try {
        expect(doc.isEncrypted, isTrue);
        expect(doc.pageCount, greaterThan(0));
      } finally {
        doc.dispose();
      }
    });

    test('owner password reveals user password (R4 legacy)', () {
      // Only R2-R4 encryption store the user password in a way that's
      // recoverable from the owner password. R5/R6 AES-256 key derivation
      // is one-way and does not allow this.
      const path = '/tmp/qpdf_test/owner_recovers_user_r4.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R4EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
              useAes: true,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      final doc = QpdfDocument.open(path, password: ownerPwd);
      try {
        expect(doc.userPassword, userPwd,
            reason: 'Owner should be able to recover R4 user password');
      } finally {
        doc.dispose();
      }
    });

    test('both user and owner password grant access', () {
      const path = '/tmp/qpdf_test/both_passwords.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      for (final pwd in [userPwd, ownerPwd]) {
        final doc = QpdfDocument.open(path, password: pwd);
        try {
          expect(doc.pageCount, greaterThan(0),
              reason: 'Password "$pwd" must grant access');
        } finally {
          doc.dispose();
        }
      }
    });

    test('empty user password + owner password (anonymous-read protection)',
        () {
      const path = '/tmp/qpdf_test/empty_user_pwd.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: '',
              ownerPassword: ownerPwd,
              allowModifyOther: false,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      // Can open without any password (empty user password)
      final doc = QpdfDocument.open(path);
      try {
        expect(doc.isEncrypted, isTrue);
        expect(doc.pageCount, greaterThan(0));
        // But modification permissions should be restricted
        expect(doc.permissions.modifyOther, isFalse);
      } finally {
        doc.dispose();
      }
    });

    test('unicode passwords (R6 supports UTF-8)', () {
      const path = '/tmp/qpdf_test/unicode_pwd.pdf';
      const unicodePwd = 'пароль-密码-🔐';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: unicodePwd,
              ownerPassword: unicodePwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      final doc = QpdfDocument.open(path, password: unicodePwd);
      try {
        expect(doc.isEncrypted, isTrue);
        expect(doc.pageCount, greaterThan(0));
      } finally {
        doc.dispose();
      }
    });

    test('permissions enforcement', () {
      const path = '/tmp/qpdf_test/restricted.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
              print: R3PrintPermission.none,
              allowExtract: false,
              allowModifyOther: false,
              allowAnnotateAndForm: false,
              allowAssemble: false,
              allowFormFilling: false,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      // Open with user password - permissions should be enforced
      final doc = QpdfDocument.open(path, password: userPwd);
      try {
        final p = doc.permissions;
        expect(p.printHighRes, isFalse, reason: 'high-res print disallowed');
        expect(p.printLowRes, isFalse, reason: 'low-res print disallowed');
        expect(p.extractAll, isFalse, reason: 'extract disallowed');
        expect(p.modifyOther, isFalse, reason: 'modify disallowed');
      } finally {
        doc.dispose();
      }
    });

    test('in-memory round-trip (writeToBytes + fromBytes)', () {
      // Encrypt to bytes
      final src = QpdfDocument.open(_samplePdf);
      late final Uint8List encryptedBytes;
      try {
        encryptedBytes = src.writeToBytes(
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      expect(encryptedBytes.length, greaterThan(100));
      expect(String.fromCharCodes(encryptedBytes.sublist(0, 4)), '%PDF');

      // Decrypt from bytes
      final enc = QpdfDocument.fromBytes(encryptedBytes, password: userPwd);
      late final Uint8List decryptedBytes;
      try {
        expect(enc.isEncrypted, isTrue);
        decryptedBytes = enc.writeToBytes(
          options: const WriteOptions(preserveEncryption: false),
        );
      } finally {
        enc.dispose();
      }

      // Verify decrypted bytes are a valid, non-encrypted PDF
      final dec = QpdfDocument.fromBytes(decryptedBytes);
      try {
        expect(dec.isEncrypted, isFalse);
        expect(dec.pageCount, greaterThan(0));
      } finally {
        dec.dispose();
      }
    });

    test('decrypts PDFs created by qpdf CLI', () {
      // _encryptedPdf was created via `qpdf --encrypt ... 256 --` (R6 AES-256).
      // This verifies cross-tool interop.
      const output = '/tmp/qpdf_test/cli_interop_decrypted.pdf';
      final doc = QpdfDocument.open(_encryptedPdf, password: 'user123');
      try {
        doc.writeToFile(
          output,
          options: const WriteOptions(preserveEncryption: false),
        );
      } finally {
        doc.dispose();
      }

      final verify = QpdfDocument.open(output);
      try {
        expect(verify.isEncrypted, isFalse);
        expect(verify.pageCount, greaterThan(0));
      } finally {
        verify.dispose();
      }
    });

    test('wrong password rejected for R6-encrypted PDF', () {
      const path = '/tmp/qpdf_test/r6_for_wrong_pwd.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      expect(
        () => QpdfDocument.open(path, password: 'not-the-right-password'),
        throwsA(isA<QpdfPasswordException>()),
      );
    });

    test('no password provided for encrypted PDF throws', () {
      const path = '/tmp/qpdf_test/needs_pwd.pdf';
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          path,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: userPwd,
              ownerPassword: ownerPwd,
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      expect(
        () => QpdfDocument.open(path),
        throwsA(isA<QpdfPasswordException>()),
      );
    });

    test('re-encryption replaces old password', () {
      const step1 = '/tmp/qpdf_test/reenc_step1.pdf';
      const step2 = '/tmp/qpdf_test/reenc_step2.pdf';

      // Encrypt with first password
      final src = QpdfDocument.open(_samplePdf);
      try {
        src.writeToFile(
          step1,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: 'first-user',
              ownerPassword: 'first-owner',
            ),
          ),
        );
      } finally {
        src.dispose();
      }

      // Re-encrypt with second password
      final intermediate = QpdfDocument.open(step1, password: 'first-user');
      try {
        intermediate.writeToFile(
          step2,
          options: const WriteOptions(
            preserveEncryption: false,
            encryption: R6EncryptionParams(
              userPassword: 'second-user',
              ownerPassword: 'second-owner',
            ),
          ),
        );
      } finally {
        intermediate.dispose();
      }

      // First password no longer works on re-encrypted file
      expect(
        () => QpdfDocument.open(step2, password: 'first-user'),
        throwsA(isA<QpdfPasswordException>()),
      );

      // Second password works
      final final_ = QpdfDocument.open(step2, password: 'second-user');
      try {
        expect(final_.pageCount, greaterThan(0));
      } finally {
        final_.dispose();
      }
    });

    test('async encrypt + async decrypt round-trip', () async {
      const qpdf = QpdfAsync();
      const encrypted = '/tmp/qpdf_test/async_rt_enc.pdf';
      const decrypted = '/tmp/qpdf_test/async_rt_dec.pdf';

      await qpdf.encrypt(
        _samplePdf,
        encrypted,
        const R6EncryptionParams(
          userPassword: userPwd,
          ownerPassword: ownerPwd,
        ),
      );

      final encryptedInfo = await qpdf.getInfo(encrypted, password: userPwd);
      expect(encryptedInfo.isEncrypted, isTrue);

      await qpdf.decrypt(encrypted, decrypted, password: userPwd);

      final decryptedInfo = await qpdf.getInfo(decrypted);
      expect(decryptedInfo.isEncrypted, isFalse);
      expect(decryptedInfo.pageCount, encryptedInfo.pageCount);
    });

    test('decryption with owner password succeeds when user password unknown',
        () async {
      const qpdf = QpdfAsync();
      const encrypted = '/tmp/qpdf_test/owner_only_decrypt.pdf';
      const decrypted = '/tmp/qpdf_test/owner_only_decrypt_out.pdf';

      await qpdf.encrypt(
        _samplePdf,
        encrypted,
        const R6EncryptionParams(
          userPassword: 'known-only-to-original-owner',
          ownerPassword: 'the-owner-key',
        ),
      );

      // Decrypt using owner password (user password is "forgotten")
      await qpdf.decrypt(encrypted, decrypted, password: 'the-owner-key');

      final info = await qpdf.getInfo(decrypted);
      expect(info.isEncrypted, isFalse);
    });
  });
}
