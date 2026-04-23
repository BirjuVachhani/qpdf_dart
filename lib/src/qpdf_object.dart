import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/qpdf_bindings.g.dart';
import 'models/enums.dart';
import 'native/error_handler.dart';
import 'native/string_utils.dart';

/// A typed, memory-safe wrapper around a qpdf object handle (`qpdf_oh`).
///
/// Object handles are lightweight integer references managed by the qpdf
/// library. They are released when the owning [QpdfDocument] is disposed,
/// or can be explicitly released via [release].
final class QpdfObject {
  final QpdfBindings _bindings;
  final qpdf_data _qpdf;
  final int _handle;
  bool _released = false;

  /// Creates a [QpdfObject] from raw FFI handles.
  ///
  /// This constructor is intended for internal use by [QpdfDocument].
  /// Prefer using factory methods on [QpdfDocument] instead.
  QpdfObject.fromHandle(this._bindings, this._qpdf, this._handle);

  /// The raw qpdf_oh handle value. For advanced use only.
  int get handle => _handle;

  void _checkNotReleased() {
    if (_released) throw StateError('QpdfObject handle has been released');
  }

  /// Releases this object handle. The underlying PDF object is not deleted,
  /// only this reference to it is invalidated.
  void release() {
    if (!_released) {
      _bindings.qpdf_oh_release(_qpdf, _handle);
      _released = true;
    }
  }

  // -- Type inspection --

  PdfObjectType get type {
    _checkNotReleased();
    return PdfObjectType.fromNative(
      _bindings.qpdf_oh_get_type_code(_qpdf, _handle),
    );
  }

  String get typeName {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_get_type_name(_qpdf, _handle));
  }

  bool get isInitialized {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_initialized(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isBool {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_bool(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isNull {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_null(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isInteger {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_integer(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isReal {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_real(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isNumber {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_number(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isName {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_name(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isString {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_string(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isOperator {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_operator(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isInlineImage {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_inline_image(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isArray {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_array(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isDictionary {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_dictionary(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isStream {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_stream(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isIndirect {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_indirect(_qpdf, _handle) == QPDF_TRUE;
  }

  bool get isScalar {
    _checkNotReleased();
    return _bindings.qpdf_oh_is_scalar(_qpdf, _handle) == QPDF_TRUE;
  }

  bool isNameAndEquals(String name) {
    _checkNotReleased();
    return using((arena) {
      return _bindings.qpdf_oh_is_name_and_equals(
            _qpdf, _handle, toCString(name, arena),
          ) ==
          QPDF_TRUE;
    });
  }

  bool isDictionaryOfType(String type, {String? subtype}) {
    _checkNotReleased();
    return using((arena) {
      return _bindings.qpdf_oh_is_dictionary_of_type(
            _qpdf,
            _handle,
            toCString(type, arena),
            subtype != null ? toCString(subtype, arena) : nullptr,
          ) ==
          QPDF_TRUE;
    });
  }

  // -- Value access --

  bool get boolValue {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_bool_value(_qpdf, _handle) == QPDF_TRUE;
  }

  int get intValue {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_int_value(_qpdf, _handle);
  }

  int get intValueAsInt {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_int_value_as_int(_qpdf, _handle);
  }

  int get uintValue {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_uint_value(_qpdf, _handle);
  }

  double get numericValue {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_numeric_value(_qpdf, _handle);
  }

  String get realValue {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_get_real_value(_qpdf, _handle));
  }

  String get nameValue {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_get_name(_qpdf, _handle));
  }

  String get stringValue {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_get_string_value(_qpdf, _handle));
  }

  String get utf8Value {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_get_utf8_value(_qpdf, _handle));
  }

  Uint8List get binaryStringValue {
    _checkNotReleased();
    return using((arena) {
      final lengthPtr = arena<Size>();
      final ptr = _bindings.qpdf_oh_get_binary_string_value(
        _qpdf, _handle, lengthPtr,
      );
      final length = lengthPtr.value;
      if (ptr == nullptr || length == 0) return Uint8List(0);
      return Uint8List.fromList(
        ptr.cast<Uint8>().asTypedList(length),
      );
    });
  }

  Uint8List get binaryUtf8Value {
    _checkNotReleased();
    return using((arena) {
      final lengthPtr = arena<Size>();
      final ptr = _bindings.qpdf_oh_get_binary_utf8_value(
        _qpdf, _handle, lengthPtr,
      );
      final length = lengthPtr.value;
      if (ptr == nullptr || length == 0) return Uint8List(0);
      return Uint8List.fromList(
        ptr.cast<Uint8>().asTypedList(length),
      );
    });
  }

  // -- Array operations --

  int get arrayLength {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_array_n_items(_qpdf, _handle);
  }

  QpdfObject arrayItemAt(int index) {
    _checkNotReleased();
    return QpdfObject.fromHandle(
      _bindings, _qpdf,
      _bindings.qpdf_oh_get_array_item(_qpdf, _handle, index),
    );
  }

  void setArrayItem(int index, QpdfObject item) {
    _checkNotReleased();
    _bindings.qpdf_oh_set_array_item(_qpdf, _handle, index, item._handle);
  }

  void insertItem(int index, QpdfObject item) {
    _checkNotReleased();
    _bindings.qpdf_oh_insert_item(_qpdf, _handle, index, item._handle);
  }

  void appendItem(QpdfObject item) {
    _checkNotReleased();
    _bindings.qpdf_oh_append_item(_qpdf, _handle, item._handle);
  }

  void eraseItem(int index) {
    _checkNotReleased();
    _bindings.qpdf_oh_erase_item(_qpdf, _handle, index);
  }

  // -- Dictionary operations --

  bool hasKey(String key) {
    _checkNotReleased();
    return using((arena) {
      return _bindings.qpdf_oh_has_key(
            _qpdf, _handle, toCString(key, arena),
          ) ==
          QPDF_TRUE;
    });
  }

  QpdfObject getKey(String key) {
    _checkNotReleased();
    return using((arena) {
      return QpdfObject.fromHandle(
        _bindings, _qpdf,
        _bindings.qpdf_oh_get_key(_qpdf, _handle, toCString(key, arena)),
      );
    });
  }

  QpdfObject getKeyIfDict(String key) {
    _checkNotReleased();
    return using((arena) {
      return QpdfObject.fromHandle(
        _bindings, _qpdf,
        _bindings.qpdf_oh_get_key_if_dict(
          _qpdf, _handle, toCString(key, arena),
        ),
      );
    });
  }

  void replaceKey(String key, QpdfObject value) {
    _checkNotReleased();
    using((arena) {
      _bindings.qpdf_oh_replace_key(
        _qpdf, _handle, toCString(key, arena), value._handle,
      );
    });
  }

  void removeKey(String key) {
    _checkNotReleased();
    using((arena) {
      _bindings.qpdf_oh_remove_key(_qpdf, _handle, toCString(key, arena));
    });
  }

  void replaceOrRemoveKey(String key, QpdfObject value) {
    _checkNotReleased();
    using((arena) {
      _bindings.qpdf_oh_replace_or_remove_key(
        _qpdf, _handle, toCString(key, arena), value._handle,
      );
    });
  }

  /// Iterates over all dictionary keys and returns them as a list.
  List<String> get dictKeys {
    _checkNotReleased();
    final keys = <String>[];
    _bindings.qpdf_oh_begin_dict_key_iter(_qpdf, _handle);
    while (_bindings.qpdf_oh_dict_more_keys(_qpdf) == QPDF_TRUE) {
      keys.add(fromCString(_bindings.qpdf_oh_dict_next_key(_qpdf)));
    }
    return keys;
  }

  bool isOrHasName(String key) {
    _checkNotReleased();
    return using((arena) {
      return _bindings.qpdf_oh_is_or_has_name(
            _qpdf, _handle, toCString(key, arena),
          ) ==
          QPDF_TRUE;
    });
  }

  // -- Stream operations --

  QpdfObject get streamDict {
    _checkNotReleased();
    return QpdfObject.fromHandle(
      _bindings, _qpdf,
      _bindings.qpdf_oh_get_dict(_qpdf, _handle),
    );
  }

  Uint8List getStreamData({
    StreamDecodeLevel decodeLevel = StreamDecodeLevel.generalized,
  }) {
    _checkNotReleased();
    return using((arena) {
      final filteredPtr = arena<Int>();
      final bufpPtr = arena<Pointer<UnsignedChar>>();
      final lenPtr = arena<Size>();

      final code = _bindings.qpdf_oh_get_stream_data(
        _qpdf, _handle, decodeLevel.toNative(),
        filteredPtr, bufpPtr, lenPtr,
      );
      if (code & QPDF_ERRORS != 0) {
        // Free buffer if allocated before throwing
        if (bufpPtr.value != nullptr) _bindings.qpdf_oh_free_buffer(bufpPtr);
        checkError(_bindings, _qpdf);
      }

      final length = lenPtr.value;
      final buf = bufpPtr.value;
      if (buf == nullptr || length == 0) return Uint8List(0);

      try {
        return Uint8List.fromList(buf.cast<Uint8>().asTypedList(length));
      } finally {
        _bindings.qpdf_oh_free_buffer(bufpPtr);
      }
    });
  }

  Uint8List getPageContentData() {
    _checkNotReleased();
    return using((arena) {
      final bufpPtr = arena<Pointer<UnsignedChar>>();
      final lenPtr = arena<Size>();

      final code = _bindings.qpdf_oh_get_page_content_data(
        _qpdf, _handle, bufpPtr, lenPtr,
      );
      if (code & QPDF_ERRORS != 0) {
        if (bufpPtr.value != nullptr) _bindings.qpdf_oh_free_buffer(bufpPtr);
        checkError(_bindings, _qpdf);
      }

      final length = lenPtr.value;
      final buf = bufpPtr.value;
      if (buf == nullptr || length == 0) return Uint8List(0);

      try {
        return Uint8List.fromList(buf.cast<Uint8>().asTypedList(length));
      } finally {
        _bindings.qpdf_oh_free_buffer(bufpPtr);
      }
    });
  }

  void replaceStreamData(
    Uint8List data, {
    QpdfObject? filter,
    QpdfObject? decodeParms,
  }) {
    _checkNotReleased();
    using((arena) {
      final buf = arena<UnsignedChar>(data.length);
      buf.cast<Uint8>().asTypedList(data.length).setAll(0, data);
      _bindings.qpdf_oh_replace_stream_data(
        _qpdf,
        _handle,
        buf,
        data.length,
        filter?._handle ?? 0,
        decodeParms?._handle ?? 0,
      );
    });
  }

  // -- Object identity --

  int get objectId {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_object_id(_qpdf, _handle);
  }

  int get generation {
    _checkNotReleased();
    return _bindings.qpdf_oh_get_generation(_qpdf, _handle);
  }

  // -- Serialization --

  String unparse() {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_unparse(_qpdf, _handle));
  }

  String unparseResolved() {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_unparse_resolved(_qpdf, _handle));
  }

  String unparseBinary() {
    _checkNotReleased();
    return fromCString(_bindings.qpdf_oh_unparse_binary(_qpdf, _handle));
  }

  // -- Transformations --

  void makeDirect() {
    _checkNotReleased();
    _bindings.qpdf_oh_make_direct(_qpdf, _handle);
  }

  QpdfObject wrapInArray() {
    _checkNotReleased();
    return QpdfObject.fromHandle(
      _bindings, _qpdf,
      _bindings.qpdf_oh_wrap_in_array(_qpdf, _handle),
    );
  }

  QpdfObject clone() {
    _checkNotReleased();
    return QpdfObject.fromHandle(
      _bindings, _qpdf,
      _bindings.qpdf_oh_new_object(_qpdf, _handle),
    );
  }

  // -- Static factory constructors --

  static QpdfObject newNull(QpdfBindings bindings, qpdf_data qpdf) =>
      QpdfObject.fromHandle(bindings, qpdf, bindings.qpdf_oh_new_null(qpdf));

  static QpdfObject newBool(
    QpdfBindings bindings, qpdf_data qpdf, bool value,
  ) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_bool(qpdf, value ? QPDF_TRUE : QPDF_FALSE),
  );

  static QpdfObject newInteger(
    QpdfBindings bindings, qpdf_data qpdf, int value,
  ) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_integer(qpdf, value),
  );

  static QpdfObject newRealFromString(
    QpdfBindings bindings, qpdf_data qpdf, String value,
  ) => using((arena) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_real_from_string(qpdf, toCString(value, arena)),
  ));

  static QpdfObject newRealFromDouble(
    QpdfBindings bindings,
    qpdf_data qpdf,
    double value, {
    int decimalPlaces = 6,
  }) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_real_from_double(qpdf, value, decimalPlaces),
  );

  static QpdfObject newName(
    QpdfBindings bindings, qpdf_data qpdf, String name,
  ) => using((arena) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_name(qpdf, toCString(name, arena)),
  ));

  static QpdfObject newString(
    QpdfBindings bindings, qpdf_data qpdf, String value,
  ) => using((arena) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_string(qpdf, toCString(value, arena)),
  ));

  static QpdfObject newUnicodeString(
    QpdfBindings bindings, qpdf_data qpdf, String utf8,
  ) => using((arena) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_new_unicode_string(qpdf, toCString(utf8, arena)),
  ));

  static QpdfObject newBinaryString(
    QpdfBindings bindings, qpdf_data qpdf, Uint8List data,
  ) => using((arena) {
    final buf = arena<Char>(data.length);
    buf.cast<Uint8>().asTypedList(data.length).setAll(0, data);
    return QpdfObject.fromHandle(
      bindings, qpdf,
      bindings.qpdf_oh_new_binary_string(qpdf, buf, data.length),
    );
  });

  static QpdfObject newArray(QpdfBindings bindings, qpdf_data qpdf) =>
      QpdfObject.fromHandle(bindings, qpdf, bindings.qpdf_oh_new_array(qpdf));

  static QpdfObject newDictionary(QpdfBindings bindings, qpdf_data qpdf) =>
      QpdfObject.fromHandle(bindings, qpdf, bindings.qpdf_oh_new_dictionary(qpdf));

  static QpdfObject newStream(QpdfBindings bindings, qpdf_data qpdf) =>
      QpdfObject.fromHandle(bindings, qpdf, bindings.qpdf_oh_new_stream(qpdf));

  static QpdfObject parse(
    QpdfBindings bindings, qpdf_data qpdf, String objectStr,
  ) => using((arena) => QpdfObject.fromHandle(
    bindings, qpdf,
    bindings.qpdf_oh_parse(qpdf, toCString(objectStr, arena)),
  ));

  static QpdfObject uninitialized(QpdfBindings bindings, qpdf_data qpdf) =>
      QpdfObject.fromHandle(bindings, qpdf, bindings.qpdf_oh_new_uninitialized(qpdf));

  @override
  String toString() {
    if (_released) return 'QpdfObject(released)';
    return 'QpdfObject(${type.name}, id=$objectId)';
  }
}
