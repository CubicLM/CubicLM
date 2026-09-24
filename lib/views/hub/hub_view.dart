/// Contains: HubView (Bottom-nav "Hub" page with Dashboard + Profile tabs).
/// Dashboard tab: greeting, advanced Active Intelligence (rings for RAM
/// + context, tok/s, chip advice), usage stats, feature shortcuts.
/// Profile tab: avatar picker, editable name, profession chips.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../controllers/chat_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/model_controller.dart';
import '../../controllers/profile_controller.dart';
import '../../core/colors.dart';
import '../../core/routes.dart';
import '../../services/chip_advice.dart';
import '../../services/device_info_service.dart';
import '../../services/inference_service.dart';
import '../../services/soc_family.dart';

part 'hub_dashboard_tab.dart';
part 'hub_profile_tab.dart';
part 'hub_widgets.dart';

/// Bottom-navigation Hub page: Dashboard + Profile tabs.
class HubView extends StatefulWidget {
  const HubView({super.key});

  @override
  State<HubView> createState() => _HubViewState();
}

class _HubViewState extends State<HubView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hub',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabs,
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800),
          unselectedLabelStyle:
              GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(LucideIcons.layoutDashboard, size: 18), text: 'Dashboard'),
            Tab(icon: Icon(LucideIcons.user, size: 18), text: 'Profile'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          HubDashboardTab(),
          HubProfileTab(),
        ],
      ),
    );
  }
}
