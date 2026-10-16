import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class PersistentTopBar extends StatelessWidget {
  final bool isSecondary;
  final String title;
  final String? subtitle;
  final String avatarInitial;
  final VoidCallback onMenuOrBack;
  final VoidCallback onNotificationTap;
  final VoidCallback onAvatarTap;

  const PersistentTopBar({
    super.key,
    required this.isSecondary,
    required this.title,
    this.subtitle,
    this.avatarInitial = 'D',
    required this.onMenuOrBack,
    required this.onNotificationTap,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final barContent = Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 16,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: kIsWeb ? 0.95 : 0.88),
        border: Border(
          bottom: BorderSide(
            color: AppColors.divider.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: Row(
            children: [
              // Left action: Back only when in secondary view (hamburger completely removed)
              if (isSecondary) ...[
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.ink,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: onMenuOrBack,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 8),
              ],

              // App Logo beside Title/Subtitle
              Container(
                margin: const EdgeInsets.only(right: 10),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.06),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Center: Title & optional subtitle
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),

              // Right actions: Notification Bell and Profile Avatar
              // 1. Notification Bell
              GestureDetector(
                onTap: onNotificationTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider, width: 1),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        size: 20,
                        color: AppColors.ink,
                      ),
                      Positioned(
                        top: 9,
                        right: 9,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFDE6854),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. Profile Avatar
              GestureDetector(
                onTap: onAvatarTap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4A2421), // Approved reference deep brown
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(74, 36, 33, 0.2),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    avatarInitial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    return RepaintBoundary(
      child: ClipRect(
        child: kIsWeb
            ? barContent
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: barContent,
              ),
      ),
    );
  }
}
