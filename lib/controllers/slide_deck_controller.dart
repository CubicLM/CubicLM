import 'dart:convert';
import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../controllers/settings_controller.dart';
import '../services/app_log_service.dart';
import '../services/cloud_service.dart';
import '../services/cubicdata/controller.dart';
import '../services/cubicdata/models.dart';
import '../services/document_extractor_service.dart';
import '../services/inference_service.dart';
import '../services/local_image_service.dart';
import '../services/web_fetch_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/export_file.dart';
import '../utils/prompt_export.dart';
import '../utils/slide_deck.dart';
import '../utils/slide_pptx.dart';

part 'slide_deck_generate.dart';
part 'slide_deck_edit.dart';
part 'slide_deck_export.dart';

/// Slide Maker: AI generates a structured deck from a topic.
class SlideDeckController extends GetxController {
  static const styles = [
    'Professional',
    'Playful',
    'Minimal',
    'Story-like',
    'Academic',
    'Creative',
    'Data-driven',
    'Pitch Deck',
  ];
  static const visualStyles = [
    'Professional',
    'Photorealistic',
    'Flat Vector',
    '3D Glossy',
    'Minimalist',
    'Cyberpunk',
    'Hand-drawn',
    'Vintage',
  ];
  static const minSlides = 3;
  static const maxSlides = 20;

  final topic = ''.obs;
  final style = 'Professional'.obs;
  final visualStyle = 'Professional'.obs;
  final audience = ''.obs;
  final slideCount = 6.obs;
  final slides = <Slide>[].obs;
  final outline = <SlideOutline>[].obs;
  final theme = SlideDeckTheme(
    name: 'Modern Terracotta',
    primaryColor: '#d97757',
    secondaryColor: '#4ade80',
    backgroundColor: '#14141c',
    textColor: '#f2f0ea',
    accentColor: '#d97757',
    fontHeading: 'Plus Jakarta Sans',
    fontBody: 'Plus Jakarta Sans',
  ).obs;

  final generating = false.obs;
  final showingOutline = false.obs;
  final useResearch = false.obs;
  final selectedDataSheetId = RxnString();
  final sourceFile = Rxn<File>();
  final inputImage = Rxn<File>();
  final stockImageBusyIndex = (-1).obs;

  final regenIndex = (-1).obs; // -1 = whole deck, else slide index
  final imageBusyIndex = (-1).obs;
  final lastError = RxnString();

  bool get hasDeck => slides.isNotEmpty;

  void setCount(int v) {
    slideCount.value = v.clamp(minSlides, maxSlides);
  }

  void setSourceFile(File? f) {
    sourceFile.value = f;
  }



  static const templates = SlideDeckControllerTemplates.templates;

}
