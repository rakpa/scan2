import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';

void main() {
  test('applyFilter returns input bytes for placeholder processor', () async {
    final input = <int>[1, 2, 3, 4];
    final out = await ImageProcessor().applyFilter(
      imageBytes: input,
      filter: ScanFilter.original,
    );
    expect(out, input);
  });
}
