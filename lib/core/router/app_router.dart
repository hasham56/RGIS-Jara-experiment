import 'package:flutter/material.dart';

import '../../features/detection/presentation/screens/camera_screen.dart';
import '../../features/gallery/domain/entities/saved_capture.dart';
import '../../features/gallery/presentation/screens/capture_detail_screen.dart';
import '../../features/gallery/presentation/screens/gallery_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/ticket/presentation/screens/ticket_form_screen.dart';
// TEMPORARILY DISABLED: Live tracking feature. Restore by uncommenting this
// import and the `HomeShell` case below (see AppRoutes.camera).
// import '../../home_shell.dart';

class AppRoutes {
  AppRoutes._();

  /// The form is the entry point and must own '/': Flutter's
  /// `defaultGenerateInitialRoutes` expands a deeper `initialRoute` into its
  /// parent segments and would build '/' first, opening the camera behind the
  /// form.
  static const String ticketForm = '/';
  static const String camera = '/camera';
  static const String gallery = '/gallery';
  static const String captureDetail = '/gallery/detail';
  static const String settings = '/settings';
}

class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.ticketForm:
        return MaterialPageRoute(builder: (_) => const TicketFormScreen());
      case AppRoutes.camera:
        // TEMPORARILY DISABLED: was `const HomeShell()`, which hosted the
        // Capture/Live bottom tabs. With Live switched off there is only one
        // destination, so the capture screen is shown directly.
        return MaterialPageRoute(builder: (_) => const CameraScreen());
      case AppRoutes.gallery:
        return MaterialPageRoute(builder: (_) => const GalleryScreen());
      case AppRoutes.captureDetail:
        final capture = settings.arguments as SavedCapture;
        return MaterialPageRoute(
          builder: (_) => CaptureDetailScreen(capture: capture),
        );
      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('Unknown route: ${settings.name}')),
          ),
        );
    }
  }
}
