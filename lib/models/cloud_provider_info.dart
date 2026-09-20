/// Cloud provider metadata for the Explore/model-switcher UI.
///
/// Split from `cloud_model_controller.dart` - plain value type.
/// Contains: id, name, description, icon, requiresKeyForList, supportsFetch, CloudProviderInfo()
library;

import 'package:flutter/material.dart';

class CloudProviderInfo {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final bool requiresKeyForList;
  final bool supportsFetch;

  const CloudProviderInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.requiresKeyForList = true,
    this.supportsFetch = true,
  });
}
