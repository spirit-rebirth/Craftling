import 'package:flutter/material.dart';

import '../../features/workspace/presentation/theme/workspace_colors.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentSection,
    required this.onOpenDashboard,
    required this.onOpenTasks,
    required this.onOpenInbox,
    required this.onOpenAgents,
    required this.onOpenWorkspace,
    required this.onOpenUsage,
    required this.onOpenSettings,
    required this.onOpenHelp,
    this.taskListContent,
  });

  final String currentSection;
  final VoidCallback onOpenDashboard;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenWorkspace;
  final VoidCallback onOpenUsage;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHelp;
  final Widget? taskListContent;

  static const double width = 340;

  @override
  Widget build(BuildContext context) {
    final bool showTaskTree =
        currentSection == 'tasks' && taskListContent != null;

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A111D),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Craftling',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SidebarNavItem(
                    icon: Icons.space_dashboard_rounded,
                    label: 'Dashboard',
                    isSelected: currentSection == 'dashboard',
                    onTap: onOpenDashboard,
                  ),
                  _SidebarNavItem(
                    icon: Icons.task_alt_rounded,
                    label: 'Tasks',
                    isSelected: currentSection == 'tasks',
                    onTap: onOpenTasks,
                  ),
                  if (showTaskTree) ...<Widget>[
                    const SizedBox(height: 4),
                    taskListContent!,
                    const SizedBox(height: 12),
                  ] else
                    const SizedBox(height: 8),
                  _SidebarNavItem(
                    icon: Icons.inbox_rounded,
                    label: 'Inbox',
                    isSelected: currentSection == 'inbox',
                    onTap: onOpenInbox,
                  ),
                  _SidebarNavItem(
                    icon: Icons.smart_toy_rounded,
                    label: 'Agents',
                    isSelected: currentSection == 'agents',
                    onTap: onOpenAgents,
                  ),
                  _SidebarNavItem(
                    icon: Icons.view_quilt_rounded,
                    label: 'Workspace',
                    isSelected: currentSection == 'workspace',
                    onTap: onOpenWorkspace,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SidebarNavItem(
            icon: Icons.query_stats_rounded,
            label: 'Usage',
            isSelected: currentSection == 'usage',
            onTap: onOpenUsage,
          ),
          _SidebarNavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: currentSection == 'settings',
            onTap: onOpenSettings,
          ),
          _SidebarNavItem(
            icon: Icons.help_outline_rounded,
            label: 'Help',
            isSelected: currentSection == 'help',
            onTap: onOpenHelp,
          ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color background = widget.isSelected
        ? selectionSurface
        : _hovered
        ? panelBackgroundAlt
        : Colors.transparent;
    final Color foreground = widget.isSelected ? textPrimary : textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.isSelected
                    ? primaryBlue.withValues(alpha: 0.42)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.icon,
                  color: widget.isSelected ? primaryBlue : foreground,
                  size: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13.5,
                      fontWeight: widget.isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
