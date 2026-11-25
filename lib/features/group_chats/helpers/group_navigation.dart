import 'dart:async';
import 'package:nexora/core/services/active_screen_tracker.dart';

/// Single decision point for "should we navigate to this group's chat
/// screen right now, or is it already the one on screen

FutureOr<T?> openGroupChat<T>(String groupId, FutureOr<T?> Function() push) {
  if (!ActiveScreenTracker.claimGroupNavigation(groupId)) return null;
  return push();
}
