import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/post.dart';
import '../theme.dart';

/// Each material has its own color and icon so it can be recognised at a
/// glance, on the post form, cards, filters and the map.
extension RecyclableStyle on RecyclableType {
  Color get color => switch (this) {
    RecyclableType.plastic => const Color(0xFF1F78B4),
    RecyclableType.glass => const Color(0xFF138A7A),
    RecyclableType.metal => const Color(0xFF5D6B78),
    RecyclableType.cardboard => const Color(0xFF9C6630),
    RecyclableType.paper => const Color(0xFF8D7A2E),
    RecyclableType.cans => const Color(0xFFB8432F),
    RecyclableType.appliances => const Color(0xFF6E4AA8),
  };

  IconData get icon => switch (this) {
    RecyclableType.plastic => Icons.local_drink,
    RecyclableType.glass => Icons.wine_bar,
    RecyclableType.metal => Icons.hardware,
    RecyclableType.cardboard => Icons.inventory_2,
    RecyclableType.paper => Icons.newspaper,
    RecyclableType.cans => Icons.sports_bar,
    RecyclableType.appliances => Icons.kitchen,
  };

  /// English name only ("Glass" from "Glass / Bote").
  String get shortLabel => label.split(' / ').first;

  /// Local name, if any ("Bote").
  String? get localLabel {
    final parts = label.split(' / ');
    return parts.length > 1 ? parts[1] : null;
  }

  /// What households usually put in this group.
  String get examples => switch (this) {
    RecyclableType.plastic => 'PET bottles, containers',
    RecyclableType.glass => 'Bottles, jars',
    RecyclableType.metal => 'Scrap iron, wires, pipes',
    RecyclableType.cardboard => 'Boxes, cartons',
    RecyclableType.paper => 'Newspapers, notebooks',
    RecyclableType.cans => 'Soda, beer, sardines cans',
    RecyclableType.appliances => 'Ref, TV, electric fan',
  };
}

extension PostStatusStyle on PostStatus {
  Color get color => switch (this) {
    PostStatus.available => Brand.available,
    PostStatus.reserved => Brand.reserved,
    PostStatus.collected => Brand.collected,
  };

  IconData get icon => switch (this) {
    PostStatus.available => Icons.hourglass_top,
    PostStatus.reserved => Icons.local_shipping,
    PostStatus.collected => Icons.task_alt,
  };

  /// How the household reads the status.
  String get householdLabel => switch (this) {
    PostStatus.available => 'Waiting for collector',
    PostStatus.reserved => 'Collector is coming',
    PostStatus.collected => 'Picked up',
  };
}

extension PostLabelStyle on PostLabel {
  Color get color => this == PostLabel.free ? Brand.free : Brand.forSale;
  IconData get icon =>
      this == PostLabel.free ? Icons.volunteer_activism : Icons.payments;
}
