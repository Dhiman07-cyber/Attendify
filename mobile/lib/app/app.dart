import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_colors.dart';
import '../shared/widgets/bottom_nav_bar.dart';
import '../shared/widgets/persistent_top_bar.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/today/today_screen.dart';
import '../features/subjects/subjects_screen.dart';
import '../features/holidays/holidays_screen.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/providers/profile_provider.dart';
import '../features/settings/settings_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import 'dart:ui';
import '../features/setup/academic_setup_screen.dart';
import '../features/setup/providers/setup_provider.dart';
import '../shared/providers/semesters_provider.dart';
import '../core/storage/local_storage.dart';

class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class AttendHubApp extends ConsumerStatefulWidget {
  const AttendHubApp({super.key});

  @override
  ConsumerState<AttendHubApp> createState() => _AttendHubAppState();
}

class _AttendHubAppState extends ConsumerState<AttendHubApp> {
  bool _hasSeenOnboarding = false;
  bool _authInitialSignUp = false;
  int _activeTabIndex = 0; // 0=Dashboard, 1=Today, 2=Subjects, 3=Calendar
  String? _secondaryRoute; // 'analytics', 'holidays', 'profile', 'settings', 'setup'
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;

  final List<int> _tabHistory = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _activeTabIndex);
    _checkOnboardingStatus();
    _restoreNavState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkOnboardingStatus() async {
    final onboarded = await LocalStorage().hasOnboarded();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = onboarded;
      });
    }
  }

  Future<void> _restoreNavState() async {
    final nav = await LocalStorage().getNavState();
    const validSecondaryRoutes = {
      'analytics',
      'holidays',
      'profile',
      'settings',
      'setup',
    };
    final safeTabIndex = nav.tabIndex.clamp(0, 4).toInt();
    final safeSecondaryRoute = nav.secondaryRoute != null &&
            validSecondaryRoutes.contains(nav.secondaryRoute)
        ? nav.secondaryRoute
        : null;
    // Older builds could persist a route name that is no longer rendered.
    // That route was then placed in the full-screen overlay and returned
    // SizedBox.shrink(), leaving users with only the background visible.
    if (safeTabIndex != nav.tabIndex || safeSecondaryRoute != nav.secondaryRoute) {
      await LocalStorage().saveNavState(
        tabIndex: safeTabIndex,
        secondaryRoute: safeSecondaryRoute,
      );
    }
    if (mounted) {
      setState(() {
        _activeTabIndex = safeTabIndex;
        _secondaryRoute = safeSecondaryRoute;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _pageController.page?.round() != safeTabIndex) {
          _pageController.jumpToPage(safeTabIndex);
        }
      });
    }
  }

  void _setNavState({
    int? tabIndex,
    String? secondaryRoute,
    bool clearSecondary = false,
    bool recordHistory = true,
  }) {
    setState(() {
      if (tabIndex != null) {
        if (recordHistory && tabIndex != _activeTabIndex) {
          _tabHistory.remove(tabIndex);
          _tabHistory.add(_activeTabIndex);
        }
        _activeTabIndex = tabIndex;
        if (_pageController.hasClients && _pageController.page?.round() != tabIndex) {
          _pageController.jumpToPage(tabIndex);
        }
      }
      if (clearSecondary) {
        _secondaryRoute = null;
      } else if (secondaryRoute != null) {
        _secondaryRoute = secondaryRoute;
      }
    });
    if (tabIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _pageController.page?.round() != _activeTabIndex) {
          _pageController.jumpToPage(_activeTabIndex);
        }
      });
    }
    LocalStorage().saveNavState(
      tabIndex: _activeTabIndex,
      secondaryRoute: _secondaryRoute,
    );
  }

  DateTime? _lastBackPressTime;

  bool _canPop() {
    return false;
  }

  void _handleBackNavigation(BuildContext context) {
    // 1. Close secondary screen if open
    if (_secondaryRoute != null) {
      _setNavState(clearSecondary: true);
      return;
    }

    // 3. Pop previous tab from history
    if (_tabHistory.isNotEmpty) {
      final prevTab = _tabHistory.removeLast();
      _setNavState(tabIndex: prevTab, recordHistory: false);
      return;
    }

    // 4. Fallback to Dashboard if not on it
    if (_activeTabIndex != 0) {
      _setNavState(tabIndex: 0, recordHistory: false);
      return;
    }

    // 5. On root Dashboard: require double-press within 2 seconds to exit app
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit AttendiFy'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.isAuthenticated == true && !next.isAuthenticated) {
        setState(() {
          _secondaryRoute = null;
          _activeTabIndex = 0;
          _tabHistory.clear();
        });
      }
    });

    final authState = ref.watch(authProvider);
    final effectiveHasSeenOnboarding = _hasSeenOnboarding || authState.isAuthenticated;

    return MaterialApp(
      title: 'AttendiFy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const SmoothScrollBehavior(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final insets = mq.viewInsets;
        if (insets.left < 0 || insets.top < 0 || insets.right < 0 || insets.bottom < 0) {
          final sanitized = EdgeInsets.fromLTRB(
            insets.left < 0 ? 0.0 : insets.left,
            insets.top < 0 ? 0.0 : insets.top,
            insets.right < 0 ? 0.0 : insets.right,
            insets.bottom < 0 ? 0.0 : insets.bottom,
          );
          return MediaQuery(
            data: mq.copyWith(viewInsets: sanitized),
            child: child ?? const SizedBox.shrink(),
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: Builder(
        builder: (context) {
          if (authState.isInitialChecking && !authState.isAuthenticated) {
            return const Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.terracotta),
                ),
              ),
            );
          }

          if (!effectiveHasSeenOnboarding) {
            return OnboardingScreen(
              onFinish: () async {
                await LocalStorage().setOnboarded(true);
                setState(() {
                  _hasSeenOnboarding = true;
                  _authInitialSignUp = false;
                });
              },
              onSignIn: () async {
                await LocalStorage().setOnboarded(true);
                setState(() {
                  _hasSeenOnboarding = true;
                  _authInitialSignUp = false;
                });
              },
              onSkip: () async {
                await LocalStorage().setOnboarded(true);
                setState(() {
                  _hasSeenOnboarding = true;
                  _authInitialSignUp = false;
                });
              },
              onCreateAccount: () async {
                await LocalStorage().setOnboarded(true);
                setState(() {
                  _hasSeenOnboarding = true;
                  _authInitialSignUp = true;
                });
              },
            );
          }

          if (!authState.isAuthenticated) {
            return AuthScreen(
              initialIsSignUp: _authInitialSignUp,
              onBack: () {
                setState(() {
                  _hasSeenOnboarding = false;
                });
              },
              onLoginSuccess: () {
                setState(() {});
              },
            );
          }

          // Authoritative Server-Side Setup Verification Check (runs in parallel without unmounting app shell)
          final setupState = ref.watch(setupProvider);
          if (setupState.status == null && !setupState.isLoading && setupState.errorMessage == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(setupProvider.notifier).checkStatus();
            });
          }

          final semState = ref.watch(semestersProvider);

          // Authenticated App Shell with Persistent Top Controls and Floating Bottom Nav
          return PopScope(
            canPop: _canPop(),
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _handleBackNavigation(context);
            },
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: AppColors.background,
              appBar: null,
              drawer: null,
              body: Stack(
                children: [
                  // 1. Primary Tabs PageView - Always kept alive in background
                  FocusScope(
                    canRequestFocus: _secondaryRoute == null,
                    child: IgnorePointer(
                      ignoring: _secondaryRoute != null,
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (index) {
                          setState(() {
                            _activeTabIndex = index;
                          });
                          LocalStorage().saveNavState(
                            tabIndex: index,
                            secondaryRoute: null,
                          );
                        },
                        children: [
                          KeepAliveWrapper(
                            child: DashboardScreen(
                              onOpenDrawer: () {},
                              onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
                              onNavigateToToday: () => _setNavState(tabIndex: 1, clearSecondary: true),
                              onNavigateToAnalytics: () => _setNavState(tabIndex: 2, clearSecondary: true),
                              onNavigateToCalendar: () => _setNavState(tabIndex: 2, clearSecondary: true),
                              onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
                            ),
                          ),
                          KeepAliveWrapper(
                            child: TodayScreen(
                              onOpenDrawer: () {},
                              onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
                              onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
                            ),
                          ),
                          KeepAliveWrapper(
                            child: AnalyticsScreen(
                              onOpenDrawer: () {},
                              onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
                              onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
                            ),
                          ),
                          KeepAliveWrapper(
                            child: SubjectsScreen(
                              onOpenDrawer: () {},
                              onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
                              onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
                            ),
                          ),
                          KeepAliveWrapper(
                            child: HolidaysScreen(
                              onOpenDrawer: () {},
                              onNavigateToCalendar: () => _setNavState(tabIndex: 2, clearSecondary: true),
                              onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
                              onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. Secondary Screen Overlay with fast, fluid slide & fade transition
                if (_secondaryRoute != null)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.04, 0.0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey<String>(_secondaryRoute!),
                          child: _buildSecondaryScreen(),
                        ),
                      ),
                    ),
                  ),

                // 3. Persistent Top App Bar (Pinned for primary tabs, analytics, and holidays)
                if (_secondaryRoute == null || _secondaryRoute == 'analytics' || _secondaryRoute == 'holidays')
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: RepaintBoundary(
                      child: PersistentTopBar(
                        isSecondary: _secondaryRoute != null,
                        title: _getBarTitle(semState),
                        subtitle: _getBarSubtitle(semState),
                        avatarInitial: _getAvatarInitial(),
                        onMenuOrBack: () {
                          if (_secondaryRoute != null) {
                            _setNavState(clearSecondary: true);
                          } else {
                            _scaffoldKey.currentState?.openDrawer();
                          }
                        },
                        onNotificationTap: () => _showNotificationsSheet(context),
                        onAvatarTap: () => _setNavState(secondaryRoute: 'profile'),
                      ),
                    ),
                  ),

                // 4. Floating Liquid Glass Bottom Navigation (Pinned only on primary screens)
                if (_secondaryRoute == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: RepaintBoundary(
                      child: LiquidGlassBottomNav(
                        currentIndex: _activeTabIndex,
                        onTap: (index) {
                          _setNavState(tabIndex: index, clearSecondary: true);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }

  String _getBarTitle(SemestersState semState) {
    if (_secondaryRoute == 'analytics') return 'AttendiFy';
    if (_secondaryRoute == 'holidays') return 'Holidays';
    switch (_activeTabIndex) {
      case 0:
      case 1:
      case 2:
      case 3:
      case 4:
      default:
        return 'AttendiFy';
    }
  }

  String _getBarSubtitle(SemestersState semState) {
    return semState.activeSemester?.label ?? '1st Semester';
  }

  String _getAvatarInitial() {
    final prof = ref.watch(profileProvider).asData?.value;
    if (prof != null && prof.fullName.trim().isNotEmpty) {
      return prof.fullName.trim()[0].toUpperCase();
    }
    final authUser = ref.watch(authProvider).user;
    if (authUser != null) {
      if (authUser.fullName.trim().isNotEmpty) {
        return authUser.fullName.trim()[0].toUpperCase();
      }
      if (authUser.avatarInitial.trim().isNotEmpty) {
        return authUser.avatarInitial.trim()[0].toUpperCase();
      }
    }
    return 'S';
  }

  Widget _buildSecondaryScreen() {
    if (_secondaryRoute == 'analytics') {
      return AnalyticsScreen(
        onOpenDrawer: () {},
        onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
        onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
      );
    } else if (_secondaryRoute == 'holidays') {
      return HolidaysScreen(
        onOpenDrawer: () {},
        onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
        onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
        onNavigateToCalendar: () {
          _setNavState(tabIndex: 2, clearSecondary: true);
        },
      );
    } else if (_secondaryRoute == 'profile') {
      return ProfileScreen(
        onBack: () => _setNavState(clearSecondary: true),
        onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
      );
    } else if (_secondaryRoute == 'settings') {
      return SettingsScreen(
        onBack: () => _setNavState(clearSecondary: true),
      );
    } else if (_secondaryRoute == 'setup') {
      return AcademicSetupScreen(
        onComplete: () {
          // setup_provider.commitSetup() already invalidated all data providers.
          // Re-check setup status and reload semester list to refresh the UI.
          ref.read(setupProvider.notifier).checkStatus();
          ref.read(semestersProvider.notifier).loadSemesters();
          _setNavState(clearSecondary: true);
        },
        onCancel: () => _setNavState(clearSecondary: true),
      );
    }
    // Never allow an unknown persisted route to render a blank full-screen
    // overlay. Clear it and fall back to the primary dashboard content.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _secondaryRoute != null) {
        _setNavState(clearSecondary: true);
      }
    });
    return DashboardScreen(
      onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      onNavigateToProfile: () => _setNavState(secondaryRoute: 'profile'),
      onNavigateToToday: () => _setNavState(tabIndex: 1, clearSecondary: true),
      onNavigateToAnalytics: () => _setNavState(tabIndex: 2, clearSecondary: true),
      onNavigateToCalendar: () => _setNavState(tabIndex: 3, clearSecondary: true),
      onOpenSetup: () => _setNavState(secondaryRoute: 'setup'),
    );
  }

  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications_rounded, color: AppColors.terracotta, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Notifications',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.ink),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Alert Card 1
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.sageLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.sageDark.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.sageDark, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '75% Attendance Guard Active',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.sageDark),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Your semester minimum policy is active. Attendance forecasting recalculates in real-time.',
                          style: TextStyle(fontSize: 11, color: AppColors.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Alert Card 2
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF6F3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule_rounded, color: AppColors.terracotta, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Schedule Synchronized',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'All timetable sessions and registered holidays are scoped to your active semester.',
                          style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.settings_outlined, size: 16, color: AppColors.terracotta),
                label: const Text(
                  'Notification Preferences',
                  style: TextStyle(color: AppColors.terracotta, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _setNavState(secondaryRoute: 'settings');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


}