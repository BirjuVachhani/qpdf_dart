import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/qpdf_bindings.g.dart';
import 'models/encryption_params.dart';
import 'models/permissions.dart';
import 'models/qpdf_exception.dart';
import 'models/write_options.dart';
import 'native/error_handler.dart';
import 'native/native_qpdf.dart';
import 'native/string_utils.dart';
import 'qpdf_object.dart';
import 'qpdf_page.dart';

/// The main entry point for PDF manipulation with qpdf.
///
/// A [QpdfDocument] represents a loaded PDF file and provides access to all
/// qpdf operations: reading, writing, encryption, page manipulation, and
/// low-level object access.
///
/// Native resources are cleaned up automatically when the document becomes
/// unreachable (via [NativeFinalizer]). For deterministic cleanup, prefer
/// calling [dispose] explicitly:
///
/// ```dart
/// final doc = QpdfDocument.open('input.pdf');
/// try {
///   print('Pages: ${doc.pageCount}');
///   doc.writeToFile('output.pdf', options: WriteOptions(linearize: true));
/// } finally {
///   doc.dispose();
/// }
/// ```
final class QpdfDocument implements Finalizable {
  /// Native finalizer that runs `qpdf_cleanup(Pointer<qpdf_data>)` if this
  /// document is garbage-collected without [dispose] being called.
  ///
  /// One finalizer instance per isolate is sufficient (see comment on
  /// [NativeQpdf]).
  static final _finalizer = NativeFinalizer(NativeQpdf.cleanupFinalizer);

  final QpdfBindings _bindings;

  /// Heap-allocated storage for the `qpdf_data*` pointer. Passed to
  /// `qpdf_cleanup` (which expects `qpdf_data**`) as both the disposal target
  /// and the [NativeFinalizer] token.
  final Pointer<qpdf_data> _handleSlot;

  /// The underlying `qpdf_data` handle read from [_handleSlot].
  qpdf_data get _handle => _handleSlot.value;

  bool _disposed = false;

  QpdfDocument._(this._bindings, qpdf_data handle)
      : _handleSlot = (malloc<qpdf_data>()..value = handle) {
    // Silence errors and warnings so callers can check them explicitly
    _bindings.qpdf_silence_errors(handle);
    _bindings.qpdf_set_suppress_warnings(handle, QPDF_TRUE);
    // Attach finalizer: if this object is GC'd without dispose, qpdf_cleanup
    // is called with _handleSlot as the argument, freeing the native data.
    _finalizer.attach(this, _handleSlot.cast(), detach: this);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('QpdfDocument has been disposed');
  }

  // -- Construction --

  /// Opens a PDF file from disk.
  ///
  /// Pass [password] if the file is encrypted.
  /// Throws [QpdfPasswordException] if the password is wrong.
  /// Throws [QpdfSystemException] if the file cannot be read.
  factory QpdfDocument.open(String path, {String? password}) {
    final bindings = NativeQpdf.bindings;
    final handle = bindings.qpdf_init();
    final doc = QpdfDocument._(bindings, handle);
    try {
      using((arena) {
        final pathPtr = toCString(path, arena);
        final passwordPtr =
            password != null ? toCString(password, arena) : nullptr;
        final code = bindings.qpdf_read(handle, pathPtr, passwordPtr);
        checkErrorCode(bindings, handle, code);
      });
    } catch (_) {
      doc.dispose();
      rethrow;
    }
    return doc;
  }

  /// Loads a PDF from an in-memory byte buffer.
  ///
  /// [description] is used in error messages in place of a filename.
  factory QpdfDocument.fromBytes(
    Uint8List bytes, {
    String? password,
    String description = 'memory',
  }) {
    final bindings = NativeQpdf.bindings;
    final handle = bindings.qpdf_init();
    final doc = QpdfDocument._(bindings, handle);
    try {
      using((arena) {
        final descPtr = toCString(description, arena);
        final passwordPtr =
            password != null ? toCString(password, arena) : nullptr;
        final buf = arena<Char>(bytes.length);
        buf.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
        final code = bindings.qpdf_read_memory(
          handle, descPtr, buf, bytes.length, passwordPtr,
        );
        checkErrorCode(bindings, handle, code);
      });
    } catch (_) {
      doc.dispose();
      rethrow;
    }
    return doc;
  }

  /// Creates an empty PDF document.
  factory QpdfDocument.empty() {
    final bindings = NativeQpdf.bindings;
    final handle = bindings.qpdf_init();
    final doc = QpdfDocument._(bindings, handle);
    try {
      final code = bindings.qpdf_empty_pdf(handle);
      checkErrorCode(bindings, handle, code);
    } catch (_) {
      doc.dispose();
      rethrow;
    }
    return doc;
  }

  /// Creates a PDF from a qpdf JSON file.
  factory QpdfDocument.fromJsonFile(String path) {
    final bindings = NativeQpdf.bindings;
    final handle = bindings.qpdf_init();
    final doc = QpdfDocument._(bindings, handle);
    try {
      using((arena) {
        final code = bindings.qpdf_create_from_json_file(
          handle, toCString(path, arena),
        );
        checkErrorCode(bindings, handle, code);
      });
    } catch (_) {
      doc.dispose();
      rethrow;
    }
    return doc;
  }

  /// Creates a PDF from a qpdf JSON data buffer.
  factory QpdfDocument.fromJsonData(Uint8List data) {
    final bindings = NativeQpdf.bindings;
    final handle = bindings.qpdf_init();
    final doc = QpdfDocument._(bindings, handle);
    try {
      using((arena) {
        final buf = arena<Char>(data.length);
        buf.cast<Uint8>().asTypedList(data.length).setAll(0, data);
        final code = bindings.qpdf_create_from_json_data(
          handle, buf, data.length,
        );
        checkErrorCode(bindings, handle, code);
      });
    } catch (_) {
      doc.dispose();
      rethrow;
    }
    return doc;
  }

  // -- Document info --

  /// The PDF version string (e.g. "1.7").
  String get pdfVersion {
    _checkNotDisposed();
    return fromCString(_bindings.qpdf_get_pdf_version(_handle));
  }

  /// The PDF extension level.
  int get extensionLevel {
    _checkNotDisposed();
    return _bindings.qpdf_get_pdf_extension_level(_handle);
  }

  /// Whether the PDF is linearized (web-optimized).
  bool get isLinearized {
    _checkNotDisposed();
    return _bindings.qpdf_is_linearized(_handle) == QPDF_TRUE;
  }

  /// Whether the PDF is encrypted.
  bool get isEncrypted {
    _checkNotDisposed();
    return _bindings.qpdf_is_encrypted(_handle) == QPDF_TRUE;
  }

  /// The user password (available after opening with owner password).
  String get userPassword {
    _checkNotDisposed();
    return fromCString(_bindings.qpdf_get_user_password(_handle));
  }

  /// The permissions set on this PDF.
  PdfPermissions get permissions {
    _checkNotDisposed();
    return PdfPermissions(
      accessibility:
          _bindings.qpdf_allow_accessibility(_handle) == QPDF_TRUE,
      extractAll: _bindings.qpdf_allow_extract_all(_handle) == QPDF_TRUE,
      printLowRes: _bindings.qpdf_allow_print_low_res(_handle) == QPDF_TRUE,
      printHighRes: _bindings.qpdf_allow_print_high_res(_handle) == QPDF_TRUE,
      modifyAssembly:
          _bindings.qpdf_allow_modify_assembly(_handle) == QPDF_TRUE,
      modifyForm: _bindings.qpdf_allow_modify_form(_handle) == QPDF_TRUE,
      modifyAnnotation:
          _bindings.qpdf_allow_modify_annotation(_handle) == QPDF_TRUE,
      modifyOther: _bindings.qpdf_allow_modify_other(_handle) == QPDF_TRUE,
      modifyAll: _bindings.qpdf_allow_modify_all(_handle) == QPDF_TRUE,
    );
  }

  // -- Info dictionary --

  /// Gets a value from the document info dictionary.
  ///
  /// [key] must include the leading slash (e.g. "/Title", "/Author").
  /// Returns `null` if the key is not present or has a non-string value.
  String? getInfoKey(String key) {
    _checkNotDisposed();
    return using((arena) {
      final result = _bindings.qpdf_get_info_key(
        _handle, toCString(key, arena),
      );
      return fromCStringNullable(result);
    });
  }

  /// Sets a value in the document info dictionary.
  ///
  /// [key] must include the leading slash (e.g. "/Title").
  /// Pass `null` as [value] to remove the key.
  void setInfoKey(String key, String? value) {
    _checkNotDisposed();
    using((arena) {
      _bindings.qpdf_set_info_key(
        _handle,
        toCString(key, arena),
        value != null ? toCString(value, arena) : nullptr,
      );
    });
  }

  /// Convenience getters for common info dictionary keys.
  String? get title => getInfoKey('/Title');
  set title(String? value) => setInfoKey('/Title', value);

  String? get author => getInfoKey('/Author');
  set author(String? value) => setInfoKey('/Author', value);

  String? get subject => getInfoKey('/Subject');
  set subject(String? value) => setInfoKey('/Subject', value);

  String? get keywords => getInfoKey('/Keywords');
  set keywords(String? value) => setInfoKey('/Keywords', value);

  String? get creator => getInfoKey('/Creator');
  set creator(String? value) => setInfoKey('/Creator', value);

  String? get producer => getInfoKey('/Producer');
  set producer(String? value) => setInfoKey('/Producer', value);

  // -- Check --

  /// Validates the PDF structure. Returns any warnings found.
  List<QpdfWarning> check() {
    _checkNotDisposed();
    final code = _bindings.qpdf_check_pdf(_handle);
    checkErrorCode(_bindings, _handle, code);
    return collectWarnings(_bindings, _handle);
  }

  // -- Read parameters --

  /// Sets whether to ignore xref streams.
  void setIgnoreXrefStreams(bool value) {
    _checkNotDisposed();
    _bindings.qpdf_set_ignore_xref_streams(
      _handle, value ? QPDF_TRUE : QPDF_FALSE,
    );
  }

  /// Sets whether to attempt recovery on damaged PDFs.
  void setAttemptRecovery(bool value) {
    _checkNotDisposed();
    _bindings.qpdf_set_attempt_recovery(
      _handle, value ? QPDF_TRUE : QPDF_FALSE,
    );
  }

  // -- JSON update --

  /// Updates this PDF from a JSON file.
  void updateFromJsonFile(String path) {
    _checkNotDisposed();
    using((arena) {
      final code = _bindings.qpdf_update_from_json_file(
        _handle, toCString(path, arena),
      );
      checkErrorCode(_bindings, _handle, code);
    });
  }

  /// Updates this PDF from JSON data.
  void updateFromJsonData(Uint8List data) {
    _checkNotDisposed();
    using((arena) {
      final buf = arena<Char>(data.length);
      buf.cast<Uint8>().asTypedList(data.length).setAll(0, data);
      final code = _bindings.qpdf_update_from_json_data(
        _handle, buf, data.length,
      );
      checkErrorCode(_bindings, _handle, code);
    });
  }

  // -- Pages --

  /// The number of pages in the document.
  int get pageCount {
    _checkNotDisposed();
    final count = _bindings.qpdf_get_num_pages(_handle);
    if (count < 0) {
      checkError(_bindings, _handle);
    }
    return count;
  }

  /// Gets a page by zero-based index.
  QpdfPage getPage(int index) {
    _checkNotDisposed();
    final oh = _bindings.qpdf_get_page_n(_handle, index);
    return QpdfPage(QpdfObject.fromHandle(_bindings, _handle, oh));
  }

  /// Returns all pages as a list.
  List<QpdfPage> get pages {
    _checkNotDisposed();
    return List.generate(pageCount, getPage);
  }

  /// Adds a page from [sourceDoc] at the front or back.
  void addPage(QpdfDocument sourceDoc, QpdfPage page, {bool first = false}) {
    _checkNotDisposed();
    final code = _bindings.qpdf_add_page(
      _handle, sourceDoc._handle, page.object.handle,
      first ? QPDF_TRUE : QPDF_FALSE,
    );
    checkErrorCode(_bindings, _handle, code);
  }

  /// Adds a page at a specific position relative to [refPage].
  void addPageAt(
    QpdfDocument sourceDoc,
    QpdfPage page, {
    required bool before,
    required QpdfPage refPage,
  }) {
    _checkNotDisposed();
    final code = _bindings.qpdf_add_page_at(
      _handle, sourceDoc._handle, page.object.handle,
      before ? QPDF_TRUE : QPDF_FALSE, refPage.object.handle,
    );
    checkErrorCode(_bindings, _handle, code);
  }

  /// Removes a page from the document.
  void removePage(QpdfPage page) {
    _checkNotDisposed();
    final code = _bindings.qpdf_remove_page(_handle, page.object.handle);
    checkErrorCode(_bindings, _handle, code);
  }

  /// Finds a page by its object ID. Returns the zero-based index.
  int findPageByObjectId(int objectId, int generation) {
    _checkNotDisposed();
    final index = _bindings.qpdf_find_page_by_id(
      _handle, objectId, generation,
    );
    if (index < 0) checkError(_bindings, _handle);
    return index;
  }

  /// Rebuilds the internal pages cache after external page tree modifications.
  void updateAllPagesCache() {
    _checkNotDisposed();
    final code = _bindings.qpdf_update_all_pages_cache(_handle);
    checkErrorCode(_bindings, _handle, code);
  }

  /// Pushes inherited page attributes down to individual pages.
  void pushInheritedAttributesToPage() {
    _checkNotDisposed();
    final code = _bindings.qpdf_push_inherited_attributes_to_page(_handle);
    checkErrorCode(_bindings, _handle, code);
  }

  // -- Low-level object access --

  /// The document trailer dictionary.
  QpdfObject get trailer {
    _checkNotDisposed();
    return QpdfObject.fromHandle(_bindings, _handle, _bindings.qpdf_get_trailer(_handle));
  }

  /// The document catalog (root object).
  QpdfObject get root {
    _checkNotDisposed();
    return QpdfObject.fromHandle(_bindings, _handle, _bindings.qpdf_get_root(_handle));
  }

  /// Gets an object by its ID and generation number.
  QpdfObject getObjectById(int objectId, int generation) {
    _checkNotDisposed();
    return QpdfObject.fromHandle(
      _bindings, _handle,
      _bindings.qpdf_get_object_by_id(_handle, objectId, generation),
    );
  }

  /// Makes an object indirect (assigns an object ID).
  QpdfObject makeIndirect(QpdfObject obj) {
    _checkNotDisposed();
    return QpdfObject.fromHandle(
      _bindings, _handle,
      _bindings.qpdf_make_indirect_object(_handle, obj.handle),
    );
  }

  /// Replaces an indirect object.
  void replaceObject(int objectId, int generation, QpdfObject obj) {
    _checkNotDisposed();
    _bindings.qpdf_replace_object(_handle, objectId, generation, obj.handle);
  }

  /// Copies an object from another PDF into this one.
  QpdfObject copyForeignObject(QpdfDocument source, QpdfObject foreignObj) {
    _checkNotDisposed();
    return QpdfObject.fromHandle(
      _bindings, _handle,
      _bindings.qpdf_oh_copy_foreign_object(
        _handle, source._handle, foreignObj.handle,
      ),
    );
  }

  // -- Object creation helpers --

  QpdfObject newNull() => QpdfObject.newNull(_bindings, _handle);
  QpdfObject newBool(bool value) =>
      QpdfObject.newBool(_bindings, _handle, value);
  QpdfObject newInteger(int value) =>
      QpdfObject.newInteger(_bindings, _handle, value);
  QpdfObject newReal(double value, {int decimalPlaces = 6}) =>
      QpdfObject.newRealFromDouble(
        _bindings, _handle, value, decimalPlaces: decimalPlaces,
      );
  QpdfObject newRealFromString(String value) =>
      QpdfObject.newRealFromString(_bindings, _handle, value);
  QpdfObject newName(String name) =>
      QpdfObject.newName(_bindings, _handle, name);
  QpdfObject newString(String value) =>
      QpdfObject.newString(_bindings, _handle, value);
  QpdfObject newUnicodeString(String utf8) =>
      QpdfObject.newUnicodeString(_bindings, _handle, utf8);
  QpdfObject newBinaryString(Uint8List data) =>
      QpdfObject.newBinaryString(_bindings, _handle, data);
  QpdfObject newArray() => QpdfObject.newArray(_bindings, _handle);
  QpdfObject newDictionary() => QpdfObject.newDictionary(_bindings, _handle);
  QpdfObject newStream() => QpdfObject.newStream(_bindings, _handle);
  QpdfObject parseObject(String objectStr) =>
      QpdfObject.parse(_bindings, _handle, objectStr);

  // -- Writing --

  /// Writes the PDF to a file.
  void writeToFile(String path, {WriteOptions options = const WriteOptions()}) {
    _checkNotDisposed();
    using((arena) {
      final code = _bindings.qpdf_init_write(_handle, toCString(path, arena));
      checkErrorCode(_bindings, _handle, code);
    });

    _applyWriteOptions(options);

    final code = _bindings.qpdf_write(_handle);
    checkErrorCode(_bindings, _handle, code);
  }

  /// Writes the PDF to memory and returns the bytes.
  Uint8List writeToBytes({WriteOptions options = const WriteOptions()}) {
    _checkNotDisposed();

    final code = _bindings.qpdf_init_write_memory(_handle);
    checkErrorCode(_bindings, _handle, code);

    _applyWriteOptions(options);

    final writeCode = _bindings.qpdf_write(_handle);
    checkErrorCode(_bindings, _handle, writeCode);

    final length = _bindings.qpdf_get_buffer_length(_handle);
    final buffer = _bindings.qpdf_get_buffer(_handle);
    if (buffer == nullptr || length == 0) return Uint8List(0);

    return Uint8List.fromList(buffer.cast<Uint8>().asTypedList(length));
  }

  void _applyWriteOptions(WriteOptions options) {
    _bindings.qpdf_set_linearization(
      _handle, options.linearize ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_qdf_mode(
      _handle, options.qdfMode ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_deterministic_ID(
      _handle, options.deterministicId ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_preserve_encryption(
      _handle, options.preserveEncryption ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_compress_streams(
      _handle, options.compressStreams ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_content_normalization(
      _handle, options.contentNormalization ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_stream_data_mode(
      _handle, options.streamDataMode.toNative(),
    );
    _bindings.qpdf_set_object_stream_mode(
      _handle, options.objectStreamMode.toNative(),
    );
    _bindings.qpdf_set_decode_level(
      _handle, options.decodeLevel.toNative(),
    );
    _bindings.qpdf_set_preserve_unreferenced_objects(
      _handle, options.preserveUnreferencedObjects ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_newline_before_endstream(
      _handle, options.newlineBeforeEndstream ? QPDF_TRUE : QPDF_FALSE,
    );
    _bindings.qpdf_set_suppress_original_object_IDs(
      _handle, options.suppressOriginalObjectIds ? QPDF_TRUE : QPDF_FALSE,
    );

    if (options.minimumPdfVersion != null) {
      using((arena) {
        if (options.minimumPdfVersionExtension != null) {
          _bindings.qpdf_set_minimum_pdf_version_and_extension(
            _handle,
            toCString(options.minimumPdfVersion!, arena),
            options.minimumPdfVersionExtension!,
          );
        } else {
          _bindings.qpdf_set_minimum_pdf_version(
            _handle, toCString(options.minimumPdfVersion!, arena),
          );
        }
      });
    }

    if (options.forcePdfVersion != null) {
      using((arena) {
        if (options.forcePdfVersionExtension != null) {
          _bindings.qpdf_force_pdf_version_and_extension(
            _handle,
            toCString(options.forcePdfVersion!, arena),
            options.forcePdfVersionExtension!,
          );
        } else {
          _bindings.qpdf_force_pdf_version(
            _handle, toCString(options.forcePdfVersion!, arena),
          );
        }
      });
    }

    if (options.encryption != null) {
      _applyEncryption(options.encryption!);
    }
  }

  void _applyEncryption(EncryptionParams params) {
    using((arena) {
      final userPwd = toCString(params.userPassword, arena);
      final ownerPwd = toCString(params.ownerPassword, arena);

      switch (params) {
        case R2EncryptionParams p:
          _bindings.qpdf_set_r2_encryption_parameters_insecure(
            _handle, userPwd, ownerPwd,
            p.allowPrint ? QPDF_TRUE : QPDF_FALSE,
            p.allowModify ? QPDF_TRUE : QPDF_FALSE,
            p.allowExtract ? QPDF_TRUE : QPDF_FALSE,
            p.allowAnnotate ? QPDF_TRUE : QPDF_FALSE,
          );
        case R3EncryptionParams p:
          _bindings.qpdf_set_r3_encryption_parameters_insecure(
            _handle, userPwd, ownerPwd,
            p.allowAccessibility ? QPDF_TRUE : QPDF_FALSE,
            p.allowExtract ? QPDF_TRUE : QPDF_FALSE,
            p.allowAssemble ? QPDF_TRUE : QPDF_FALSE,
            p.allowAnnotateAndForm ? QPDF_TRUE : QPDF_FALSE,
            p.allowFormFilling ? QPDF_TRUE : QPDF_FALSE,
            p.allowModifyOther ? QPDF_TRUE : QPDF_FALSE,
            p.print.toNative(),
          );
        case R4EncryptionParams p:
          _bindings.qpdf_set_r4_encryption_parameters_insecure(
            _handle, userPwd, ownerPwd,
            p.allowAccessibility ? QPDF_TRUE : QPDF_FALSE,
            p.allowExtract ? QPDF_TRUE : QPDF_FALSE,
            p.allowAssemble ? QPDF_TRUE : QPDF_FALSE,
            p.allowAnnotateAndForm ? QPDF_TRUE : QPDF_FALSE,
            p.allowFormFilling ? QPDF_TRUE : QPDF_FALSE,
            p.allowModifyOther ? QPDF_TRUE : QPDF_FALSE,
            p.print.toNative(),
            p.encryptMetadata ? QPDF_TRUE : QPDF_FALSE,
            p.useAes ? QPDF_TRUE : QPDF_FALSE,
          );
        case R5EncryptionParams p:
          _bindings.qpdf_set_r5_encryption_parameters2(
            _handle, userPwd, ownerPwd,
            p.allowAccessibility ? QPDF_TRUE : QPDF_FALSE,
            p.allowExtract ? QPDF_TRUE : QPDF_FALSE,
            p.allowAssemble ? QPDF_TRUE : QPDF_FALSE,
            p.allowAnnotateAndForm ? QPDF_TRUE : QPDF_FALSE,
            p.allowFormFilling ? QPDF_TRUE : QPDF_FALSE,
            p.allowModifyOther ? QPDF_TRUE : QPDF_FALSE,
            p.print.toNative(),
            p.encryptMetadata ? QPDF_TRUE : QPDF_FALSE,
          );
        case R6EncryptionParams p:
          _bindings.qpdf_set_r6_encryption_parameters2(
            _handle, userPwd, ownerPwd,
            p.allowAccessibility ? QPDF_TRUE : QPDF_FALSE,
            p.allowExtract ? QPDF_TRUE : QPDF_FALSE,
            p.allowAssemble ? QPDF_TRUE : QPDF_FALSE,
            p.allowAnnotateAndForm ? QPDF_TRUE : QPDF_FALSE,
            p.allowFormFilling ? QPDF_TRUE : QPDF_FALSE,
            p.allowModifyOther ? QPDF_TRUE : QPDF_FALSE,
            p.print.toNative(),
            p.encryptMetadata ? QPDF_TRUE : QPDF_FALSE,
          );
      }
    });
  }

  // -- Lifecycle --

  /// Releases all native resources held by this document.
  ///
  /// Calling [dispose] is optional — if omitted, the document is cleaned up
  /// automatically by a [NativeFinalizer] when garbage-collected. However,
  /// explicit disposal gives deterministic cleanup which is strongly
  /// recommended for tight loops or memory-sensitive applications. After
  /// disposal, all methods throw [StateError].
  ///
  /// Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Detach finalizer first so it doesn't also run on this handle.
    _finalizer.detach(this);
    // Release all object handles, then clean up the qpdf_data. qpdf_cleanup
    // reads *_handleSlot, frees the data, and writes NULL back into the slot.
    _bindings.qpdf_oh_release_all(_handle);
    _bindings.qpdf_cleanup(_handleSlot);
    // Free the heap slot itself.
    malloc.free(_handleSlot);
  }

  @override
  String toString() {
    if (_disposed) return 'QpdfDocument(disposed)';
    return 'QpdfDocument(version=$pdfVersion, pages=$pageCount)';
  }
}
