/// Pure helpers for the Thermal tab (moved verbatim out of the tab
/// file so header/curve/group cards share one source).
String thermalStatusLabel(int s) {
  switch (s) {
    case 0:
      return 'Normal';
    case 1:
      return 'Light';
    case 2:
      return 'Moderate';
    case 3:
      return 'Severe';
    case 4:
      return 'Critical';
    case 5:
      return 'Emergency';
    case 6:
      return 'Shutdown';
    default:
      return '—';
  }
}

String thermalGroupOf(String name) {
  final n = name.toLowerCase();
  if (n.startsWith('cpu-') || n.startsWith('cpuss-')) {
    return 'CPU';
  }
  if (n.startsWith('gpu')) return 'GPU';
  if (n.startsWith('ddr-')) return 'Memory';
  if (n == 'battery') return 'Battery';
  if (n.startsWith('camera-')) return 'Camera';
  return 'Other';
}

String thermalTemp(dynamic v) {
  final d = (v as num?)?.toDouble();
  if (d == null) return '—';
  return '${d.toStringAsFixed(1)} °C';
}
