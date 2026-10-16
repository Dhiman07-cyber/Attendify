import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_radii.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/brand_icons.dart';
import '../../shared/widgets/app_toast.dart';
import 'providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  final VoidCallback onLoginSuccess;
  final VoidCallback? onBack;
  final bool initialIsSignUp;

  const AuthScreen({
    super.key,
    required this.onLoginSuccess,
    this.onBack,
    this.initialIsSignUp = false,
  });

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late bool _isSignUp;
  bool _obscurePassword = true;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initialIsSignUp;
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty) {
      AppToast.showError(context, 'Please enter your email address.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      AppToast.showError(context, 'Please enter a valid email address.');
      return;
    }
    if (password.isEmpty) {
      AppToast.showError(context, 'Please enter your password.');
      return;
    }

    if (_isSignUp) {
      if (password.length < 6) {
        AppToast.showError(context, 'Password must be at least 6 characters long.');
        return;
      }
      final success = await ref.read(authProvider.notifier).register(
            email: email,
            password: password,
            fullName: name.isNotEmpty ? name : 'New Student',
          );
      if (success) {
        // Trigger Google Password Manager / OS autofill prompt to save credentials on native platforms
        if (!kIsWeb) {
          try {
            TextInput.finishAutofillContext(shouldSave: true);
          } catch (_) {}
        }
        widget.onLoginSuccess();
      }
    } else {
      final success =
          await ref.read(authProvider.notifier).login(email, password);
      if (success) {
        // Trigger Google Password Manager / OS autofill prompt to save credentials on native platforms
        if (!kIsWeb) {
          try {
            TextInput.finishAutofillContext(shouldSave: true);
          } catch (_) {}
        }
        widget.onLoginSuccess();
      }
    }
  }

  void _handleGoogleSignIn() async {
    final success = await ref.read(authProvider.notifier).signInWithGoogle();
    if (success && mounted) {
      widget.onLoginSuccess();
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.errorMessage != null &&
          next.errorMessage != previous?.errorMessage &&
          mounted) {
        AppToast.showError(context, next.errorMessage!);
      }
    });

    final authState = ref.watch(authProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final availableHeight = constraints.maxHeight;
            // Banner height dynamically scales so the campus illustration is beautifully visible
            final bannerHeight =
                (availableHeight * 0.28).clamp(180.0, 240.0) + topPadding;
            const cardTopRadius = 24.0;
            final bannerVisibleHeight = bannerHeight - cardTopRadius;
            final bottomPadding = MediaQuery.of(context).padding.bottom;
            final formMinHeight =
                (availableHeight - bannerVisibleHeight).clamp(0.0, double.infinity);

            // Proportional spacing calculation: distribute extra vertical room naturally
            final baseFormHeight = _isSignUp ? 460.0 : 390.0;
            final extraHeight =
                (formMinHeight - baseFormHeight).clamp(0.0, _isSignUp ? 110.0 : 90.0);

            final spacingHeaderToFields = 10.0 + extraHeight * 0.14;
            final spacingBetweenFields = 9.0 + extraHeight * 0.08;
            final spacingFieldsToSubmit = 10.0 + extraHeight * 0.14;
            final spacingSubmitToOr = 9.0 + extraHeight * 0.10;
            final spacingOrToGoogle = 9.0 + extraHeight * 0.10;
            final spacingGoogleToFooter = 12.0 + extraHeight * 0.32;

            return Stack(
              children: [
                // -----------------------------------------------------------
                // 1. STATIONARY TOP BACKGROUND IMAGE: Pinned behind the card
                // Stays fixed at the top of the viewport; never scrolls away.
                // -----------------------------------------------------------
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: bannerHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/login.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            'assets/images/login_header.png',
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                          );
                        },
                      ),
                      // Soft warm theme overlay
                      Container(
                        color: const Color(0xFFF7F1EC).withValues(alpha: 0.08),
                      ),

                      // Floating AttendHub logo squircle badge with smooth scroll-driven transition
                      Positioned(
                        top: topPadding,
                        bottom: cardTopRadius,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _scrollController,
                            builder: (context, _) {
                              final offset = _scrollController.hasClients
                                  ? _scrollController.offset
                                  : 0.0;
                              final progress = (offset / 100.0).clamp(0.0, 1.0);
                              final scale = 1.0 - (0.22 * progress);
                              final opacity =
                                  (1.0 - (progress * 1.25)).clamp(0.0, 1.0);
                              final translateY = -15.0 * progress;

                              return Transform.translate(
                                offset: Offset(0, translateY),
                                child: Transform.scale(
                                  scale: scale,
                                  child: Opacity(
                                    opacity: opacity,
                                    child: Container(
                                      width: 62,
                                      height: 62,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        boxShadow: const [
                                          BoxShadow(
                                            color:
                                                Color.fromRGBO(0, 0, 0, 0.14),
                                            blurRadius: 18,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: Image.asset(
                                            'assets/images/app_icon.png',
                                            width: 46,
                                            height: 46,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // -----------------------------------------------------------
                // 2. SCROLLABLE FORM CARD
                // Overlaps the background image and glides upwards on scroll.
                // -----------------------------------------------------------
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        // Transparent top spacer exposing the background graphic
                        SizedBox(height: bannerVisibleHeight),

                        // Form Card Sheet with rounded top corners & elevated shadow
                        Container(
                          constraints: BoxConstraints(minHeight: formMinHeight),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(cardTopRadius),
                              topRight: Radius.circular(cardTopRadius),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 18,
                                offset: const Offset(0, -4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              16,
                              24,
                              (bottomPadding + 18).clamp(18.0, 36.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title & Subtitle
                                Center(
                                  child: Text(
                                    _isSignUp ? 'Create Account' : 'Welcome Back',
                                    style: AppTypography.displayLarge.copyWith(
                                      fontSize: 25,
                                      height: 1.18,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'serif',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Center(
                                  child: Text(
                                    _isSignUp
                                        ? 'Register to track your attendance independently'
                                        : 'Log in to continue to AttendiFy',
                                    style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.inkMuted,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                SizedBox(height: spacingHeaderToFields),

                                // Form Fields with Google Password Manager Autofill
                                AutofillGroup(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_isSignUp) ...[
                                        AppTextField(
                                          label: 'Full Name',
                                          hint: 'Enter your full name',
                                          controller: _nameController,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [AutofillHints.name],
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.person_outline_rounded,
                                            size: 22,
                                            color: AppColors.inkMuted,
                                          ),
                                        ),
                                        SizedBox(height: spacingBetweenFields),
                                      ],

                                      AppTextField(
                                        label: 'Email / University ID',
                                        hint: 'Enter your email or university ID',
                                        controller: _emailController,
                                        keyboardType: TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.email,
                                          AutofillHints.username,
                                        ],
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.mail_outline_rounded,
                                          size: 22,
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                      SizedBox(height: spacingBetweenFields),

                                      AppTextField(
                                        label: 'Password',
                                        hint: 'Enter your password',
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        autofillHints: _isSignUp
                                            ? const [AutofillHints.newPassword]
                                            : const [AutofillHints.password],
                                        onEditingComplete: _submit,
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 16,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.lock_outline_rounded,
                                          size: 22,
                                          color: AppColors.inkMuted,
                                        ),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            size: 22,
                                            color: AppColors.inkMuted,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword = !_obscurePassword;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Forgot Password Link (Log In mode only)
                                if (!_isSignUp) ...[
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () {
                                        AppToast.showInfo(
                                          context,
                                          'Password reset instructions sent to registered email.',
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text(
                                        'Forgot Password?',
                                        style: AppTypography.bodySmall.copyWith(
                                          color: const Color(0xFFDE6854),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                SizedBox(height: spacingFieldsToSubmit),

                                // Submit Button
                                AppButton(
                                  label: _isSignUp ? 'Create Account' : 'Log In',
                                  isLoading: authState.isSubmitting,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 15, horizontal: 20),
                                  onPressed: (authState.isSubmitting || authState.isGoogleLoading) ? null : _submit,
                                ),
                                SizedBox(height: spacingSubmitToOr),

                                // "or" Divider
                                const Row(
                                  children: [
                                    Expanded(
                                        child:
                                            Divider(color: Color(0xFFEADBCE), thickness: 1)),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 14),
                                      child: Text(
                                        'or',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.inkMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                        child:
                                            Divider(color: Color(0xFFEADBCE), thickness: 1)),
                                  ],
                                ),
                                SizedBox(height: spacingOrToGoogle),

                                // Social Login Button (Google only)
                                _buildSocialButton(
                                  logo: authState.isGoogleLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.terracotta),
                                          ),
                                        )
                                      : BrandIcons.google(size: 22),
                                  label: authState.isGoogleLoading ? 'Processing...' : 'Continue with Google',
                                  onTap: (authState.isGoogleLoading || authState.isSubmitting)
                                      ? () {}
                                      : _handleGoogleSignIn,
                                ),

                                SizedBox(height: spacingGoogleToFooter),

                                // Switch between Log In and Sign Up (Horizontally Centered)
                                Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        _isSignUp
                                            ? 'Already have an account? '
                                            : "Don't have an account? ",
                                        style: AppTypography.bodySmall.copyWith(fontSize: 13),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                                          setState(() {
                                            _isSignUp = !_isSignUp;
                                          });
                                          if (_scrollController.hasClients) {
                                            _scrollController.animateTo(
                                              0.0,
                                              duration: const Duration(milliseconds: 250),
                                              curve: Curves.easeOut,
                                            );
                                          }
                                        },
                                        child: Text(
                                          _isSignUp ? 'Sign In' : 'Sign Up',
                                          style: AppTypography.bodySmall.copyWith(
                                            color: const Color(0xFFDE6854),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // -----------------------------------------------------------
                // 3. TOP PINNED CONTROLS: Status Bar Protection Gradient & Native Back Button
                // -----------------------------------------------------------
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topPadding + 44,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.transparent,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: topPadding + 10,
                  left: 16,
                  child: InkWell(
                    onTap: _handleBack,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.08),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required Widget logo,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.radiusXl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadii.radiusXl,
          border: Border.all(color: const Color(0xFFEDE4DB), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.02),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
