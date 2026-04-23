import '../bindings/qpdf_bindings.g.dart';

/// PDF object type classification.
enum PdfObjectType {
  uninitialized,
  reserved,
  null_,
  boolean,
  integer,
  real,
  string,
  name,
  array,
  dictionary,
  stream,
  operator_,
  inlineImage,
  unresolved,
  destroyed,
  reference;

  static PdfObjectType fromNative(qpdf_object_type_e type) => switch (type) {
    qpdf_object_type_e.ot_uninitialized => uninitialized,
    qpdf_object_type_e.ot_reserved => reserved,
    qpdf_object_type_e.ot_null => null_,
    qpdf_object_type_e.ot_boolean => boolean,
    qpdf_object_type_e.ot_integer => integer,
    qpdf_object_type_e.ot_real => real,
    qpdf_object_type_e.ot_string => string,
    qpdf_object_type_e.ot_name => name,
    qpdf_object_type_e.ot_array => array,
    qpdf_object_type_e.ot_dictionary => dictionary,
    qpdf_object_type_e.ot_stream => stream,
    qpdf_object_type_e.ot_operator => operator_,
    qpdf_object_type_e.ot_inlineimage => inlineImage,
    qpdf_object_type_e.ot_unresolved => unresolved,
    qpdf_object_type_e.ot_destroyed => destroyed,
    qpdf_object_type_e.ot_reference => reference,
  };
}

/// Controls how object streams are handled during write.
enum ObjectStreamMode {
  /// Disable object streams.
  disable,
  /// Preserve existing object streams.
  preserve,
  /// Generate new object streams.
  generate;

  qpdf_object_stream_e toNative() => switch (this) {
    disable => qpdf_object_stream_e.qpdf_o_disable,
    preserve => qpdf_object_stream_e.qpdf_o_preserve,
    generate => qpdf_object_stream_e.qpdf_o_generate,
  };
}

/// Controls how stream data compression is handled during write.
enum StreamDataMode {
  /// Uncompress all stream data.
  uncompress,
  /// Preserve existing compression.
  preserve,
  /// Compress all stream data.
  compress;

  qpdf_stream_data_e toNative() => switch (this) {
    uncompress => qpdf_stream_data_e.qpdf_s_uncompress,
    preserve => qpdf_stream_data_e.qpdf_s_preserve,
    compress => qpdf_stream_data_e.qpdf_s_compress,
  };
}

/// Controls how deep stream decoding goes.
enum StreamDecodeLevel {
  /// Preserve all stream filters.
  none,
  /// Decode general-purpose filters.
  generalized,
  /// Also decode other non-lossy filters.
  specialized,
  /// Also decode lossy filters.
  all;

  qpdf_stream_decode_level_e toNative() => switch (this) {
    none => qpdf_stream_decode_level_e.qpdf_dl_none,
    generalized => qpdf_stream_decode_level_e.qpdf_dl_generalized,
    specialized => qpdf_stream_decode_level_e.qpdf_dl_specialized,
    all => qpdf_stream_decode_level_e.qpdf_dl_all,
  };
}

/// How stream data is included in JSON output.
enum JsonStreamData {
  /// Omit stream data.
  none,
  /// Embed stream data inline in JSON.
  inline,
  /// Reference stream data from files.
  file;

  qpdf_json_stream_data_e toNative() => switch (this) {
    none => qpdf_json_stream_data_e.qpdf_sj_none,
    inline => qpdf_json_stream_data_e.qpdf_sj_inline,
    file => qpdf_json_stream_data_e.qpdf_sj_file,
  };
}

/// Print permissions for R3+ encryption.
enum R3PrintPermission {
  /// Allow full printing.
  full,
  /// Allow only low-resolution printing.
  low,
  /// Disallow printing entirely.
  none;

  qpdf_r3_print_e toNative() => switch (this) {
    full => qpdf_r3_print_e.qpdf_r3p_full,
    low => qpdf_r3_print_e.qpdf_r3p_low,
    none => qpdf_r3_print_e.qpdf_r3p_none,
  };
}

/// Modification permissions for R3 encryption.
enum R3ModifyPermission {
  /// All editing allowed.
  all,
  /// Comments, fill forms, signing, assembly.
  annotate,
  /// Fill forms, signing, assembly.
  form,
  /// Only document assembly.
  assembly,
  /// No modifications.
  none;

  qpdf_r3_modify_e toNative() => switch (this) {
    all => qpdf_r3_modify_e.qpdf_r3m_all,
    annotate => qpdf_r3_modify_e.qpdf_r3m_annotate,
    form => qpdf_r3_modify_e.qpdf_r3m_form,
    assembly => qpdf_r3_modify_e.qpdf_r3m_assembly,
    none => qpdf_r3_modify_e.qpdf_r3m_none,
  };
}
