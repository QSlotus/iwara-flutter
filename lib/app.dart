import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/account_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/startup_screen.dart';
import 'screens/video_screen.dart';
import 'services/app_controller.dart';
import 'theme.dart';

/// Used by video player pages to pause when covered by another route.
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

class IwaraApp extends StatelessWidget {
  const IwaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iwara Signal Desk',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [routeObserver],
      home: Consumer<AppController>(
        builder: (context, controller, _) {
          if (!controller.ready) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!controller.entered) {
            return const StartupScreen();
          }
          return const RootShell();
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

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int index = 0;
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
