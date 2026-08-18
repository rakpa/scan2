import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/library/data/document_storage.dart';
import 'package:scan2/features/library/domain/document.dart';
import 'package:scan2/features/library/domain/document_repository.dart';

/// On-disk document library.
///
/// Pages live under `<appDocuments>/documents/<docId>/` and a single JSON
/// manifest alongside them records titles, page order, crop quads and filter
/// settings.
///
/// Page locations are persisted *relative* to the documents root and resolved
/// on load. iOS reassigns the application container path between installs and
/// upgrades, so absolute paths written today become dangling references after
/// the next TestFlight build — every thumbnail in the library would come back
/// as a broken-image icon.
class DocumentStore implements DocumentRepository {
  DocumentStore({DocumentStorage? storage})
    : _storage = storage ?? DocumentStorage();

  static const _manifestName = 'library.json';
  static const _manifestVersion = 2;
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.heic'};

  final DocumentStorage _storage;

  final List<Document> _documents = [];
  int _nextId = 1;
  bool _loaded = false;

  /// Serialises manifest writes so two saves cannot interleave.
  Future<void> _writeChain = Future.value();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(p.join(await _storage.rootPath(), _manifestName));
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return;
      await _restore(raw);
    } catch (e) {
      // A corrupt manifest must not cost the user their library; the page
      // files are still on disk and can be adopted directly.
      debugPrint('Library manifest unreadable, rebuilding from disk: $e');
      await _rebuildFromDisk();
    }
  }

  Future<void> _restore(Map<String, dynamic> raw) async {
    final root = await _storage.rootPath();
    final documents = raw['documents'];
    if (documents is! List) return;

    for (final entry in documents) {
      if (entry is! Map) continue;
      final id = entry['id'];
      if (id is! int) continue;

      final pages = <ScanPage>[];
      final rawPages = entry['pages'];
      if (rawPages is List) {
        for (final rawPage in rawPages) {
          final page = _pageFromJson(rawPage, root);
          if (page != null) pages.add(page);
        }
      }
      if (pages.isEmpty) continue;

      _documents.add(
        Document(
          id: id,
          title: entry['title'] as String? ?? 'Scan',
          createdAt:
              DateTime.tryParse(entry['createdAt'] as String? ?? '') ??
              DateTime.now(),
          pages: pages,
          edgesAlreadyApplied: entry['edgesAlreadyApplied'] as bool? ?? false,
        ),
      );
    }

    _documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final storedNext = raw['nextId'];
    _nextId = storedNext is int && storedNext > _highestId()
        ? storedNext
        : _highestId() + 1;
  }

  ScanPage? _pageFromJson(Object? raw, String root) {
    // v1 manifests stored each page as a bare relative path string.
    if (raw is String) return ScanPage(path: p.join(root, raw));
    if (raw is! Map) return null;

    final relative = raw['path'];
    if (relative is! String) return null;

    final originalRelative = raw['original'];
    return ScanPage(
      path: p.join(root, relative),
      originalPath: originalRelative is String
          ? p.join(root, originalRelative)
          : null,
      quad: _quadFromJson(raw['quad']),
      adjustments: _adjustmentsFromJson(raw['adjustments']),
    );
  }

  static Quad? _quadFromJson(Object? raw) {
    if (raw is! List || raw.length != 8) return null;
    final v = [for (final n in raw) (n as num).toDouble()];
    return Quad(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
  }

  static List<double> _quadToJson(Quad q) => [
    q.topLeft.dx,
    q.topLeft.dy,
    q.topRight.dx,
    q.topRight.dy,
    q.bottomRight.dx,
    q.bottomRight.dy,
    q.bottomLeft.dx,
    q.bottomLeft.dy,
  ];

  static ScanAdjustments _adjustmentsFromJson(Object? raw) {
    if (raw is! Map) return const ScanAdjustments();
    final filterIndex = raw['filter'];
    return ScanAdjustments(
      filter: filterIndex is int && filterIndex < ScanFilter.values.length
          ? ScanFilter.values[filterIndex]
          : ScanFilter.original,
      brightness: (raw['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (raw['contrast'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Last-resort recovery: adopt whatever page files exist on disk.
  Future<void> _rebuildFromDisk() async {
    _documents.clear();
    try {
      final root = Directory(await _storage.rootPath());
      if (!await root.exists()) return;

      for (final entity in root.listSync().whereType<Directory>()) {
        final id = int.tryParse(
          p.basename(entity.path).replaceFirst('doc_', ''),
        );
        if (id == null) continue;

        final files =
            entity
                .listSync()
                .whereType<File>()
                .map((f) => f.path)
                .where((path) => _imageExtensions.contains(p.extension(path)))
                .toList()
              ..sort();

        // Originals sit beside their page as `<name>.orig.jpg`; they are
        // sources, not pages in their own right.
        final pages = files
            .where((path) => !p.basename(path).contains('.orig.'))
            .map(
              (path) => ScanPage(
                path: path,
                originalPath: files.contains(_originalPathFor(path))
                    ? _originalPathFor(path)
                    : null,
              ),
            )
            .toList();
        if (pages.isEmpty) continue;

        _documents.add(
          Document(
            id: id,
            title: 'Recovered scan $id',
            createdAt: entity.statSync().modified,
            pages: pages,
          ),
        );
      }
      _documents.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _nextId = _highestId() + 1;
      await _persist();
    } catch (e) {
      debugPrint('Library recovery failed: $e');
    }
  }

  static String _originalPathFor(String pagePath) {
    final extension = p.extension(pagePath);
    return '${p.withoutExtension(pagePath)}.orig$extension';
  }

  int _highestId() =>
      _documents.fold<int>(0, (max, d) => d.id > max ? d.id : max);

  @override
  Future<List<Document>> getAllDocuments() async {
    await ensureLoaded();
    return List.unmodifiable(_documents);
  }

  @override
  Future<Document?> getDocument(int id) async {
    await ensureLoaded();
    for (final doc in _documents) {
      if (doc.id == id) return doc;
    }
    return null;
  }

  @override
  Future<Document> createDocumentFromScans(
    List<String> sourcePaths, {
    String? title,
    bool edgesAlreadyApplied = false,
  }) async {
    if (sourcePaths.isEmpty) {
      throw ArgumentError('sourcePaths must not be empty');
    }
    await ensureLoaded();

    final now = DateTime.now();
    final id = _nextId++;
    final pages = <ScanPage>[];
    for (var i = 0; i < sourcePaths.length; i++) {
      pages.add(
        ScanPage(
          path: await _storage.importPage(
            documentId: 'doc_$id',
            index: i,
            sourcePath: sourcePaths[i],
          ),
        ),
      );
    }

    final doc = Document(
      id: id,
      title: title ?? defaultTitle(now),
      createdAt: now,
      pages: pages,
      edgesAlreadyApplied: edgesAlreadyApplied,
    );
    _documents.insert(0, doc);
    await _persist();
    return doc;
  }

  /// Creates a document from pages that have already been processed.
  ///
  /// [processedBytes] is the finished image and [originalPaths] the capture it
  /// came from, so the crop screen can re-derive rather than re-edit a JPEG
  /// that has already been through the pipeline once.
  Future<Document> createProcessedDocument({
    required List<ProcessedPage> pages,
    String? title,
  }) async {
    if (pages.isEmpty) throw ArgumentError('pages must not be empty');
    await ensureLoaded();

    final now = DateTime.now();
    final id = _nextId++;
    final stored = <ScanPage>[];
    for (var i = 0; i < pages.length; i++) {
      stored.add(await _writeProcessedPage('doc_$id', i, pages[i]));
    }

    final doc = Document(
      id: id,
      title: title ?? defaultTitle(now),
      createdAt: now,
      pages: stored,
    );
    _documents.insert(0, doc);
    await _persist();
    return doc;
  }

  Future<ScanPage> _writeProcessedPage(
    String documentId,
    int index,
    ProcessedPage page,
  ) async {
    final pagePath = await _storage.importPage(
      documentId: documentId,
      index: index,
      sourcePath: page.originalPath,
    );
    // The import placed the original at the page slot; move it aside and put
    // the processed image in its place.
    final originalPath = _originalPathFor(pagePath);
    await File(pagePath).rename(originalPath);
    await _storage.writePageBytes(pagePath: pagePath, bytes: page.bytes);

    return ScanPage(
      path: pagePath,
      originalPath: originalPath,
      quad: page.quad,
      adjustments: page.adjustments,
    );
  }

  /// Appends already-processed pages to an existing document.
  Future<Document?> addProcessedPages(
    int documentId,
    List<ProcessedPage> pages,
  ) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;

    final existing = _documents[index];
    final added = <ScanPage>[];
    for (var i = 0; i < pages.length; i++) {
      added.add(
        await _writeProcessedPage(
          'doc_$documentId',
          existing.pageCount + i,
          pages[i],
        ),
      );
    }

    final updated = existing.copyWith(pages: [...existing.pages, ...added]);
    _documents[index] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<Document?> addPages(int documentId, List<String> sourcePaths) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;

    final existing = _documents[index];
    final added = <ScanPage>[];
    for (var i = 0; i < sourcePaths.length; i++) {
      added.add(
        ScanPage(
          path: await _storage.importPage(
            documentId: 'doc_$documentId',
            index: existing.pageCount + i,
            sourcePath: sourcePaths[i],
          ),
        ),
      );
    }

    final updated = existing.copyWith(pages: [...existing.pages, ...added]);
    _documents[index] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<Document?> replacePageBytes({
    required int documentId,
    required String pagePath,
    required List<int> bytes,
    Quad? quad,
    ScanAdjustments? adjustments,
  }) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;

    await _storage.writePageBytes(pagePath: pagePath, bytes: bytes);

    final doc = _documents[index];
    final updated = doc.copyWith(
      pages: [
        for (final page in doc.pages)
          if (page.path == pagePath)
            page.copyWith(quad: quad, adjustments: adjustments)
          else
            page,
      ],
    );
    _documents[index] = updated;
    await _persist();
    return updated;
  }

  @override
  Future<Document?> findDocumentByPagePath(String pagePath) async {
    await ensureLoaded();
    for (final doc in _documents) {
      if (doc.pagePaths.contains(pagePath)) return doc;
    }
    return null;
  }

  @override
  Future<void> renameDocument(int id, String title) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == id);
    if (index == -1) return;
    _documents[index] = _documents[index].copyWith(title: title);
    await _persist();
  }

  @override
  Future<void> deleteDocument(int id) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == id);
    if (index == -1) return;
    _documents.removeAt(index);
    // Persist the removal before touching files, so a crash mid-delete leaves
    // orphaned files rather than entries pointing at nothing.
    await _persist();
    await _storage.deleteDocumentFiles('doc_$id');
  }

  @override
  Future<void> deletePage({
    required int documentId,
    required String pagePath,
  }) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return;

    final doc = _documents[index];
    final removed = doc.pageAt(pagePath);
    final remaining = doc.pages.where((page) => page.path != pagePath).toList();
    if (remaining.isEmpty) {
      await deleteDocument(documentId);
      return;
    }

    _documents[index] = doc.copyWith(pages: remaining);
    await _persist();
    for (final path in [pagePath, removed?.originalPath]) {
      if (path == null) continue;
      try {
        await File(path).delete();
      } catch (_) {
        // Already gone; the manifest is the source of truth.
      }
    }
  }

  /// Reorders pages within a document.
  Future<Document?> reorderPages(
    int documentId,
    int oldIndex,
    int newIndex,
  ) async {
    await ensureLoaded();
    final index = _documents.indexWhere((d) => d.id == documentId);
    if (index == -1) return null;

    final doc = _documents[index];
    if (oldIndex < 0 || oldIndex >= doc.pageCount) return doc;
    final pages = [...doc.pages];
    final page = pages.removeAt(oldIndex);
    pages.insert(newIndex.clamp(0, pages.length), page);

    final updated = doc.copyWith(pages: pages);
    _documents[index] = updated;
    await _persist();
    return updated;
  }

  Future<void> _persist() {
    // Chained rather than concurrent: a batch scan finishes several saves
    // within a frame, and interleaved writes corrupt the manifest.
    _writeChain = _writeChain.then((_) => _writeManifest());
    return _writeChain;
  }

  Future<void> _writeManifest() async {
    try {
      final root = await _storage.rootPath();
      String rel(String path) => p.relative(path, from: root);

      final payload = <String, dynamic>{
        'version': _manifestVersion,
        'nextId': _nextId,
        'documents': [
          for (final doc in _documents)
            {
              'id': doc.id,
              'title': doc.title,
              'createdAt': doc.createdAt.toIso8601String(),
              'edgesAlreadyApplied': doc.edgesAlreadyApplied,
              'pages': [
                for (final page in doc.pages)
                  {
                    'path': rel(page.path),
                    if (page.originalPath != null)
                      'original': rel(page.originalPath!),
                    if (page.quad != null) 'quad': _quadToJson(page.quad!),
                    'adjustments': {
                      'filter': page.adjustments.filter.index,
                      'brightness': page.adjustments.brightness,
                      'contrast': page.adjustments.contrast,
                    },
                  },
              ],
            },
        ],
      };

      // Write to a sibling then rename: a half-written manifest would cost the
      // user their whole library.
      final target = File(p.join(root, _manifestName));
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(jsonEncode(payload), flush: true);
      await temp.rename(target.path);
    } catch (e) {
      debugPrint('Failed to save library manifest: $e');
    }
  }

  static String defaultTitle(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'Scan ${two(now.month)}/${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
  }

  Future<void> close() async {
    await _writeChain;
  }
}

/// A captured page that has already been cropped and enhanced, along with the
/// settings used, so the edit can be reopened later.
@immutable
class ProcessedPage {
  const ProcessedPage({
    required this.originalPath,
    required this.bytes,
    this.quad,
    this.adjustments = const ScanAdjustments(),
  });

  final String originalPath;
  final Uint8List bytes;
  final Quad? quad;
  final ScanAdjustments adjustments;
}
