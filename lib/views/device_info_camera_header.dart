import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'device_info_camera_list_item.dart';

/// Horizontal camera selector + the manufacturer-limitation note.
/// Purely presentational: [cards] are pre-parsed view-models
/// (memoized upstream), so this strip never parses pixel arrays.
class CameraSelectorStrip extends StatelessWidget {
  final List<CameraCardView> cards;
  final int selected;
  final ValueChanged<int> onSelect;

  const CameraSelectorStrip({
    super.key,
    required this.cards,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 12),
        itemBuilder: (_, i) => CameraCardItem(
          card: cards[i],
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

/// Manufacturer-limitation note (exact original text/style).
class CameraNote extends StatelessWidget {
  const CameraNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Please Read This: if the MegaPixel count shown is wrong, that means your device manufacturer has limited the access to the camera for third-party apps.',
      style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          height: 1.5,
          color: Theme.of(context).hintColor),
    );
  }
}
