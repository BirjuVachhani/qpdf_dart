/// Represents the permissions set on an encrypted PDF.
final class PdfPermissions {
  final bool accessibility;
  final bool extractAll;
  final bool printLowRes;
  final bool printHighRes;
  final bool modifyAssembly;
  final bool modifyForm;
  final bool modifyAnnotation;
  final bool modifyOther;
  final bool modifyAll;

  const PdfPermissions({
    required this.accessibility,
    required this.extractAll,
    required this.printLowRes,
    required this.printHighRes,
    required this.modifyAssembly,
    required this.modifyForm,
    required this.modifyAnnotation,
    required this.modifyOther,
    required this.modifyAll,
  });

  @override
  String toString() => 'PdfPermissions('
      'print: ${printHighRes ? "high" : printLowRes ? "low" : "none"}, '
      'extract: $extractAll, '
      'modify: $modifyAll)';
}
