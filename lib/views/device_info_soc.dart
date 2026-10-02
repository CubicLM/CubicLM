/// Static SoC spec database for the CPU tab header card.
///
/// Marketing names, core clusters and process nodes are NOT measurable
/// on-device — they come from this table, matched by hardware string
/// (e.g. "SM8150"). Unknown chips fall back to measured data only
/// (no fake marketing lines).
class SocCluster {
  final int count;
  final String core;
  final String ghz;
  const SocCluster(this.count, this.core, this.ghz);

  String get line => '$count x $core ($ghz GHz)';
}

class SocSpec {
  final List<String> keys; // lowercase hardware substrings
  final String name;
  final List<SocCluster> clusters;
  final String process;
  const SocSpec(this.keys, this.name, this.clusters, this.process);
}

const _socTable = [
  SocSpec(
      ['sm8150'],
      'Qualcomm Snapdragon 855',
      [
        SocCluster(1, 'Kryo 485 Prime', '2.84'),
        SocCluster(3, 'Kryo 485 Gold', '2.42'),
        SocCluster(4, 'Kryo 485 Silver', '1.78'),
      ],
      '7 nm TSMC'),
  SocSpec(
      ['sm8250'],
      'Qualcomm Snapdragon 865',
      [
        SocCluster(1, 'Kryo 585 Prime', '2.84'),
        SocCluster(3, 'Kryo 585 Gold', '2.42'),
        SocCluster(4, 'Kryo 585 Silver', '1.80'),
      ],
      '7 nm TSMC'),
  SocSpec(
      ['sm8350'],
      'Qualcomm Snapdragon 888',
      [
        SocCluster(1, 'Cortex-X1', '2.84'),
        SocCluster(3, 'Cortex-A78', '2.42'),
        SocCluster(4, 'Cortex-A55', '1.80'),
      ],
      '5 nm Samsung'),
  SocSpec(
      ['sm8450'],
      'Qualcomm Snapdragon 8 Gen 1',
      [
        SocCluster(1, 'Cortex-X2', '3.00'),
        SocCluster(3, 'Cortex-A710', '2.50'),
        SocCluster(4, 'Cortex-A510', '1.80'),
      ],
      '4 nm Samsung'),
  SocSpec(
      ['sm8475'],
      'Qualcomm Snapdragon 8+ Gen 1',
      [
        SocCluster(1, 'Cortex-X2', '3.20'),
        SocCluster(3, 'Cortex-A710', '2.75'),
        SocCluster(4, 'Cortex-A510', '2.00'),
      ],
      '4 nm TSMC'),
  SocSpec(
      ['sm8550'],
      'Qualcomm Snapdragon 8 Gen 2',
      [
        SocCluster(1, 'Cortex-X3', '3.20'),
        SocCluster(2, 'Cortex-A715', '2.80'),
        SocCluster(2, 'Cortex-A710', '2.80'),
        SocCluster(3, 'Cortex-A510', '2.00'),
      ],
      '4 nm TSMC'),
  SocSpec(
      ['sm8650'],
      'Qualcomm Snapdragon 8 Gen 3',
      [
        SocCluster(1, 'Cortex-X4', '3.30'),
        SocCluster(3, 'Cortex-A720', '3.20'),
        SocCluster(2, 'Cortex-A720', '3.00'),
        SocCluster(2, 'Cortex-A520', '2.30'),
      ],
      '4 nm TSMC'),
  SocSpec(
      ['sm8750'],
      'Qualcomm Snapdragon 8 Elite',
      [
        SocCluster(2, 'Oryon', '4.32'),
        SocCluster(6, 'Oryon', '3.53'),
      ],
      '3 nm TSMC'),
  SocSpec(
      ['sm7325'],
      'Qualcomm Snapdragon 778G',
      [
        SocCluster(1, 'Kryo 670 Prime', '2.40'),
        SocCluster(3, 'Kryo 670 Gold', '2.20'),
        SocCluster(4, 'Kryo 670 Silver', '1.90'),
      ],
      '6 nm TSMC'),
  SocSpec(
      ['sm6375'],
      'Qualcomm Snapdragon 695',
      [
        SocCluster(2, 'Kryo 660 Gold', '2.20'),
        SocCluster(6, 'Kryo 660 Silver', '1.70'),
      ],
      '6 nm TSMC'),
  SocSpec(
      ['sm6225'],
      'Qualcomm Snapdragon 680',
      [
        SocCluster(4, 'Kryo 265 Gold', '2.40'),
        SocCluster(4, 'Kryo 265 Silver', '1.90'),
      ],
      '6 nm TSMC'),
  SocSpec(
      ['mt6983'],
      'MediaTek Dimensity 9000',
      [
        SocCluster(1, 'Cortex-X2', '3.05'),
        SocCluster(3, 'Cortex-A710', '2.85'),
        SocCluster(4, 'Cortex-A510', '1.80'),
      ],
      '4 nm TSMC'),
  SocSpec(
      ['mt6877'],
      'MediaTek Dimensity 900',
      [
        SocCluster(2, 'Cortex-A78', '2.40'),
        SocCluster(6, 'Cortex-A55', '2.00'),
      ],
      '6 nm TSMC'),
  SocSpec(
      ['mt6833'],
      'MediaTek Dimensity 700',
      [
        SocCluster(2, 'Cortex-A76', '2.20'),
        SocCluster(6, 'Cortex-A55', '2.00'),
      ],
      '7 nm TSMC'),
  SocSpec(
      ['gs201'],
      'Google Tensor G2',
      [
        SocCluster(2, 'Cortex-X1', '2.85'),
        SocCluster(2, 'Cortex-A78', '2.35'),
        SocCluster(4, 'Cortex-A55', '1.80'),
      ],
      '5 nm Samsung'),
  // NOTE: zumapro must precede zuma — 'zumapro'.contains('zuma').
  SocSpec(
      ['zumapro'],
      'Google Tensor G4',
      [
        SocCluster(1, 'Cortex-X4', '3.10'),
        SocCluster(3, 'Cortex-A720', '2.60'),
        SocCluster(4, 'Cortex-A520', '1.92'),
      ],
      '4 nm Samsung'),
  SocSpec(
      ['zuma'],
      'Google Tensor G3',
      [
        SocCluster(1, 'Cortex-X3', '2.91'),
        SocCluster(4, 'Cortex-A715', '2.37'),
        SocCluster(4, 'Cortex-A510', '1.70'),
      ],
      '4 nm Samsung'),
  SocSpec(
      ['exynos2100', 'universal2100'],
      'Samsung Exynos 2100',
      [
        SocCluster(1, 'Cortex-X1', '2.90'),
        SocCluster(3, 'Cortex-A78', '2.80'),
        SocCluster(4, 'Cortex-A55', '2.20'),
      ],
      '5 nm Samsung'),
  SocSpec(
      ['s5e9925', 'exynos2200', 'universal9925'],
      'Samsung Exynos 2200',
      [
        SocCluster(1, 'Cortex-X2', '2.80'),
        SocCluster(3, 'Cortex-A710', '2.52'),
        SocCluster(4, 'Cortex-A510', '1.82'),
      ],
      '4 nm Samsung'),
  SocSpec(
      ['hi3680', 'kirin9000'],
      'HiSilicon Kirin 9000',
      [
        SocCluster(1, 'Cortex-A77', '3.13'),
        SocCluster(3, 'Cortex-A77', '2.54'),
        SocCluster(4, 'Cortex-A55', '2.05'),
      ],
      '5 nm TSMC'),
];

/// RAM type/speed per chip (public specs, conservative list).
/// Unknown chips return null and the UI shows the measured total only.
const _ramTable = {
  'sm8150': 'LPDDR4X 2133 MHz',
  'sm8450': 'LPDDR5 3200 MHz',
  'sm8475': 'LPDDR5 3200 MHz',
  'sm8550': 'LPDDR5X 4200 MHz',
  'sm8650': 'LPDDR5X 4800 MHz',
  'sm8750': 'LPDDR5X 5333 MHz',
  'sm7325': 'LPDDR5 3200 MHz',
  'sm6375': 'LPDDR4X 2133 MHz',
  'sm6225': 'LPDDR4X 2133 MHz',
  'mt6983': 'LPDDR5X 3750 MHz',
  'mt6833': 'LPDDR4X 2133 MHz',
  'gs201': 'LPDDR5 3200 MHz',
  'zumapro': 'LPDDR5X 4200 MHz',
  'zuma': 'LPDDR5X 4200 MHz',
  'exynos2100': 'LPDDR5 2750 MHz',
  's5e9925': 'LPDDR5 3200 MHz',
};

String? ramFor(String hardware) {
  final h = hardware.toLowerCase();
  if (h.isEmpty) return null;
  for (final e in _ramTable.entries) {
    if (h.contains(e.key)) return e.value;
  }
  return null;
}

/// Returns the marketing spec when [hardware] matches, else null
/// (caller falls back to measured data only).
SocSpec? socSpecFor(String hardware) {
  final h = hardware.toLowerCase();
  if (h.isEmpty) return null;
  for (final s in _socTable) {
    for (final k in s.keys) {
      if (h.contains(k)) return s;
    }
  }
  return null;
}
