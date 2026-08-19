/// What the in-app camera is being asked to capture.
enum ScanMode {
  idCard('ID Card'),
  document('Document'),
  book('Book'),
  whiteboard('Whiteboard');

  const ScanMode(this.label);

  final String label;
}
