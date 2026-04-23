import 'dart:typed_data';

import 'qpdf_object.dart';

/// Represents a single page in a PDF document.
///
/// A page is backed by a [QpdfObject] representing the page dictionary.
/// Page objects are created by [QpdfDocument] and should not be constructed
/// directly.
final class QpdfPage {
  /// The underlying PDF object for this page.
  final QpdfObject object;

  QpdfPage(this.object);

  /// The object ID of this page.
  int get objectId => object.objectId;

  /// The generation number of this page.
  int get generation => object.generation;

  /// Returns the concatenated content stream data for this page.
  Uint8List getContentData() => object.getPageContentData();

  /// Returns the page dictionary as a [QpdfObject].
  QpdfObject get dictionary => object;

  /// Releases the underlying object handle.
  void release() => object.release();

  @override
  String toString() => 'QpdfPage(objectId=$objectId)';
}
