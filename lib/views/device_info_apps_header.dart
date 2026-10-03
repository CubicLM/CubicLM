import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Filter/count header for the Apps tab: total-count chip plus
/// User / System / All filter chips and the Analyze entry point.
/// Purely presentational — [filter] and the callbacks are owned by
/// the parent body so this widget never touches GetX/Rx.
class AppsFilterHeader extends StatelessWidget {
  final int totalCount;
  final int filter; // 0 user, 1 system, 2 all
  final ValueChanged<int> onFilter;
  final VoidCallback onAnalyze;

  const AppsFilterHeader({
    super.key,
    required this.totalCount,
    required this.filter,
    required this.onFilter,
    required this.onAnalyze,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _countChip(context, '$totalCount'),
            const SizedBox(width: 8),
            _filterChip(context, 'User', 0),
            const SizedBox(width: 8),
            _filterChip(context, 'System', 1),
            const SizedBox(width: 8),
            _filterChip(context, 'All', 2),
            const SizedBox(width: 8),
            _filterChip(context, 'Analyze', -1),
          ],
        ),
      ),
    );
  }

  Widget _countChip(BuildContext context, String s) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(s,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).hintColor)),
    );
  }

  Widget _filterChip(BuildContext context, String s, int idx) {
    if (idx == -1) {
      return InkWell(
        onTap: onAnalyze,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(s,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).hintColor)),
        ),
      );
    }
    final sel = filter == idx;
    return InkWell(
      onTap: () => onFilter(idx),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? Theme.of(context)
                  .primaryColor
                  .withValues(alpha: 0.15)
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel
                ? Theme.of(context)
                    .primaryColor
                    .withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Text(s,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: sel
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).hintColor)),
      ),
    );
  }
}
