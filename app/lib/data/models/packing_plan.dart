import 'package:freezed_annotation/freezed_annotation.dart';

import 'wardrobe_item.dart';

part 'packing_plan.freezed.dart';
part 'packing_plan.g.dart';

/// A trip packing list (CLAUDE.md §24). Maps the `POST /v1/packing/plan` response;
/// items are full wardrobe pieces so the app renders them straight away.
@freezed
abstract class PackingPlan with _$PackingPlan {
  const factory PackingPlan({
    required String title,
    @Default('') String notes,
    @Default(<WardrobeItem>[]) List<WardrobeItem> items,
  }) = _PackingPlan;

  factory PackingPlan.fromJson(Map<String, dynamic> json) =>
      _$PackingPlanFromJson(json);
}
