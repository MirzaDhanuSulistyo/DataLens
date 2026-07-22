String formatBytes(num bytes, {int fractionDigits = 1}) {
  final value = bytes < 0 ? 0 : bytes;
  if (value >= 1000 * 1000 * 1000) {
    return '${(value / 1000 / 1000 / 1000).toStringAsFixed(fractionDigits)} GB';
  }
  if (value >= 1000 * 1000) {
    return '${(value / 1000 / 1000).toStringAsFixed(fractionDigits)} MB';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)} KB';
  }
  return '${value.toStringAsFixed(0)} B';
}

String formatBitsPerSecond(double bits) {
  if (!bits.isFinite || bits < 0) return '—';
  if (bits >= 1000 * 1000) {
    return '${(bits / 1000 / 1000).toStringAsFixed(1)} Mbps';
  }
  if (bits >= 1000) {
    return '${(bits / 1000).toStringAsFixed(0)} Kbps';
  }
  return '${bits.toStringAsFixed(0)} bps';
}
