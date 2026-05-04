import 'package:flutter/material.dart';

import '../../features/workspace/presentation/theme/workspace_colors.dart';
import '../../features/workspace/presentation/widgets/workspace_shared.dart';
import '../widgets/app_sidebar.dart';

class PlaceholderSectionPage extends StatelessWidget {
  const PlaceholderSectionPage({
    super.key,
    required this.currentRoute,
    required this.title,
    required this.message,
  });

  final String currentRoute;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              AppSidebar(
                currentSection: currentRoute.replaceFirst('/', ''),
                onOpenDashboard: () {},
                onOpenTasks: () {},
                onOpenInbox: () {},
                onOpenAgents: () {},
                onOpenWorkspace: () {},
                onOpenUsage: () {},
                onOpenSettings: () {},
                onOpenHelp: () {},
              ),
              const SizedBox(width: 20),
              Expanded(
                child: PanelShell(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.construction_rounded,
                            color: textSecondary,
                            size: 40,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
