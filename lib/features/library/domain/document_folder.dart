import 'package:flutter/foundation.dart';

/// A local library category, e.g. Invoices or Receipts.
///
/// These live only on the device, under the "My Documents" root shown on
/// Screen 11. Nothing is uploaded.
@immutable
class DocumentFolder {
  const DocumentFolder({required this.id, required this.name});

  final int id;
  final String name;

  static const invoicesId = 1;

  static const defaults = [
    DocumentFolder(id: invoicesId, name: 'Invoices'),
    DocumentFolder(id: 2, name: 'Receipts'),
    DocumentFolder(id: 3, name: 'IDs'),
    DocumentFolder(id: 4, name: 'Personal'),
  ];

  String get locationLabel => 'My Documents > $name';
}
