import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:signal_desk/core/update/update_service.dart';
import 'package:signal_desk/core/update/update_ui.dart';

import 'screens/account_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/video_screen.dart';
import 'services/app_controller.dart';
import 'theme.dart';

/// Used by video player pages to pause when covered by another route.
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

/// Iwara module root. Edge first-run is handled by the Signal Desk shell.
class IwaraModuleApp extends StatelessWidget {
  const IwaraModuleApp({super.key, this.onExitModule});

  final VoidCallback? onExitModule;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AppController>();
    controller.onExitModule = onExitModule;

    return MaterialApp(
      title: 'Iwara',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [routeObserver],
      home: Consumer<AppController>(
        builder: (context, controller, _) {
          if (!controller.ready) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return const IwaraRootShell();
        },
      ),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        if (name.startsWith('/video/')) {
          final id = name.substring('/video/'.length);
          return MaterialPageRoute(builder: (_) => VideoScreen(videoId: id));
        }
        if (name.startsWith('/account/')) {
          final id = name.substring('/account/'.length);
          return MaterialPageRoute(builder: (_) => AccountScreen(profileId: id));
        }
        return null;
      },
    );
  }
}

class IwaraRootShell extends StatefulWidget {
  const IwaraRootShell({super.key});

  @override
  State<IwaraRootShell> createState() => _IwaraRootShellState();
}

class _IwaraRootShellState extends State<IwaraRootShell> {
  int index = 0;
  final UpdateService _updateService = UpdateService();
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesQuietly();
    });
  }

  Future<void> _checkForUpdatesQuietly() async {
    if (_updateChecked || !mounted) return;
    _updateChecked = true;
    try {
      final result = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (!await _updateService.shouldAutoPrompt(result)) return;
      if (!mounted) return;
      await presentUpdateCheck(
        context,
        service: _updateService,
        result: result,
        quietIfNoUpdate: true,
        markPromptedOnShow: true,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [HomeScreen(), ExploreScreen(), LibraryScreen(), AccountScreen()];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: '探索'),
          NavigationDestination(icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: '资料库'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '账户'),
        ],
      ),
    );
  }
}
