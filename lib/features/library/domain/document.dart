class Document {
  final int id;
  final String title;
  final DateTime createdAt;
  final List<String> pagePaths;
  final int? folderId;

  /// True when pages were produced by the native auto-edge scanner and are
  /// already perspective-cropped.
  final bool edgesAlreadyApplied;

  const Document({
    required this.id,
    required this.title,
    required this.createdAt,
    this.pagePaths = const [],
    this.folderId,
    this.edgesAlreadyApplied = false,
  });

  int get pageCount => pagePaths.length;

  Document copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    List<String>? pagePaths,
    int? folderId,
    bool? edgesAlreadyApplied,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      pagePaths: pagePaths ?? this.pagePaths,
      folderId: folderId ?? this.folderId,
      edgesAlreadyApplied: edgesAlreadyApplied ?? this.edgesAlreadyApplied,
    );
  }
}
