import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/library/domain/document.dart';

/// Everything the UI needs from the document library.
///
/// The library screens used to hold the store as `dynamic` and cast at each
/// call site, which meant a renamed method failed at runtime instead of at
/// compile time. One interface, two implementations: on-disk on mobile, and
/// in-memory for the browser demo where there is no file system.
abstract class DocumentRepository {
  Future<List<Document>> getAllDocuments();

  Future<Document?> getDocument(int id);

  /// Imports scanner output as a new document.
  Future<Document> createDocumentFromScans(
    List<String> sourcePaths, {
    String? title,
    bool edgesAlreadyApplied = false,
  });

  /// Appends pages to an existing document.
  Future<Document?> addPages(int documentId, List<String> sourcePaths);

  /// Overwrites one page's image, e.g. after crop and enhance.
  Future<Document?> replacePageBytes({
    required int documentId,
    required String pagePath,
    required List<int> bytes,
    Quad? quad,
    ScanAdjustments? adjustments,
  });

  Future<Document?> findDocumentByPagePath(String pagePath);

  Future<void> renameDocument(int id, String title);

  Future<void> deleteDocument(int id);

  Future<void> deletePage({required int documentId, required String pagePath});
}
