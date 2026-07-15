class Document {
  final int id;
  final String title;
  final DateTime createdAt;
  final int pageCount;
  final int? folderId;

  const Document({
    required this.id,
    required this.title,
    required this.createdAt,
    this.pageCount = 0,
    this.folderId,
  });

  Document copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    int? pageCount,
    int? folderId,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      pageCount: pageCount ?? this.pageCount,
      folderId: folderId ?? this.folderId,
    );
  }
}