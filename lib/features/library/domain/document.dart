class Document {
  final int id;
  final String title;
  final DateTime createdAt;
  final List<String> pagePaths;
  final int? folderId;

  const Document({
    required this.id,
    required this.title,
    required this.createdAt,
    this.pagePaths = const [],
    this.folderId,
  });

  int get pageCount => pagePaths.length;

  Document copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    List<String>? pagePaths,
    int? folderId,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      pagePaths: pagePaths ?? this.pagePaths,
      folderId: folderId ?? this.folderId,
    );
  }
}
