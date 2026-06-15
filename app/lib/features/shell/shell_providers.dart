import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Named shell tab indices — keep in sync with `MainShell._tabs` and the
/// floating nav slot order.
abstract final class ShellTabs {
  static const home = 0;
  static const closet = 1;
  static const tryOn = 2;
  static const community = 3;
  static const profile = 4;
}

/// The currently selected shell tab. Exposing it as a provider lets any screen
/// jump tabs (e.g. Home's "Start Try-On" → Try-On tab) without a reference to
/// the shell widget.
class ShellTab extends Notifier<int> {
  @override
  int build() => ShellTabs.home;

  void select(int index) => state = index;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);
