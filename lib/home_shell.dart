import 'package:flutter/material.dart';

import 'features/detection/presentation/screens/camera_screen.dart';
// TEMPORARILY DISABLED: Live tracking. The tab is still shown, but greyed out
// and labelled "Coming soon", so the screen is never constructed. Restore by
// uncommenting this import, the `1 => const LiveCameraScreen()` branch, and
// the `_liveEnabled` flag below.
// import 'features/live_tracking/presentation/screens/live_camera_screen.dart';
import 'features/video_processing/presentation/screens/video_record_screen.dart';

/// Bottom tab switcher between the capture-based detection flow
/// ([CameraScreen]), the live camera tracking flow (currently disabled), and
/// the record-then-batch-process flow ([VideoRecordScreen]).
///
/// Deliberately a plain widget swap (`switch (_index) { ... }`), not an
/// `IndexedStack` — each screen opens an exclusive [CameraController], and
/// most platforms only allow one open at a time. A widget swap disposes the
/// inactive screen (releasing its camera) and creates the newly-active one
/// fresh.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Flip back to `true` (and restore the import/branch above) to re-enable
  /// the Live tab.
  static const bool _liveEnabled = false;

  int _index = 0;

  void _onDestinationSelected(int index) {
    if (index == 1 && !_liveEnabled) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Live detection is coming soon.')),
        );
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final disabledColor = Theme.of(context).disabledColor;

    return Scaffold(
      body: switch (_index) {
        0 => const CameraScreen(),
        // 1 => const LiveCameraScreen(),  // TEMPORARILY DISABLED
        _ => const VideoRecordScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Capture',
          ),
          // Left tappable rather than using NavigationDestination.enabled so
          // the tap can explain itself via the snackbar above; the greyed
          // icon and label already read as unavailable.
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined, color: disabledColor),
            label: 'Live (soon)',
            tooltip: 'Live detection is coming soon',
          ),
          const NavigationDestination(
            icon: Icon(Icons.movie_creation_outlined),
            selectedIcon: Icon(Icons.movie_creation),
            label: 'Record',
          ),
        ],
      ),
    );
  }
}
