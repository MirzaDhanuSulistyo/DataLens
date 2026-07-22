import 'package:datalens/core/formatters/byte_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats decimal byte units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1500), '2 KB');
    expect(formatBytes(1280000000), '1.3 GB');
  });

  test('formats transfer rates', () {
    expect(formatBitsPerSecond(8400000), '8.4 Mbps');
    expect(formatBitsPerSecond(-1), '—');
  });
}
