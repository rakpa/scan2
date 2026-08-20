import 'package:flutter/foundation.dart';

/// A local library category, e.g. Invoices or Receipts.
///
/// These live only on the device, under the "My Documents" root shown on
/// Screen 11 and Screen 12. Nothing is uploaded.
@immutable
class DocumentFolder {
  const DocumentFolder({required this.id, required this.name});

  final int id;
  final String name;

  static const invoicesId = 1;
  static const receiptsId = 2;
  static const notesId = 3;
  static const idCardsId = 4;
  static const otherId = 5;

  static const defaults = [
    DocumentFolder(id: invoicesId, name: 'Invoices'),
    DocumentFolder(id: receiptsId, name: 'Receipts'),
    DocumentFolder(id: notesId, name: 'Notes'),
    DocumentFolder(id: idCardsId, name: 'ID Cards'),
    DocumentFolder(id: otherId, name: 'Other'),
  ];

  static const chipNames = [
    'All',
    'Invoices',
    'Receipts',
    'Notes',
    'ID Cards',
    'Other',
  ];

  String get locationLabel => 'My Documents > $name';
}
