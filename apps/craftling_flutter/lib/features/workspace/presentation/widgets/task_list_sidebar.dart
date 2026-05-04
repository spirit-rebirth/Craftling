import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import '../theme/workspace_colors.dart';
import 'workspace_shared.dart';

class TaskListSidebar extends StatelessWidget {
  const TaskListSidebar({
    super.key,
    required this.selectedTaskId,
    required this.activeTasks,
    required this.waitingTasks,
    required this.reviewTasks,
    required this.completedTasks,
    required this.failedTasks,
    required this.isSettingsSelected,
    required this.isUsageSelected,
    required this.isBackendOnline,
    required this.groupExpanded,
    required this.onNewTask,
    required this.onOpenSettings,
    required this.onOpenUsage,
    required this.onTaskSelected,
    required this.onToggleGroup,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
  });

  final String? selectedTaskId;
  final List<TaskWorkspaceData> activeTasks;
  final List<TaskWorkspaceData> waitingTasks;
  final List<TaskWorkspaceData> reviewTasks;
  final List<TaskWorkspaceData> completedTasks;
  final List<TaskWorkspaceData> failedTasks;
  final bool isSettingsSelected;
  final bool isUsageSelected;
  final bool isBackendOnline;
  final Map<String, bool> groupExpanded;
  final VoidCallback onNewTask;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenUsage;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: PanelShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'Tasks',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: onNewTask,
                      style: TextButton.styleFrom(
                        foregroundColor: textPrimary,
                        backgroundColor: primaryBlue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Task'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      SidebarTaskGroup(
                        title: 'Active',
                        items: activeTasks,
                        selectedTaskId: selectedTaskId,
                        isExpanded: groupExpanded['Active'] ?? true,
                        onToggle: () => onToggleGroup('Active'),
                        onTaskSelected: onTaskSelected,
                        onPinTask: onPinTask,
                        onRenameTask: onRenameTask,
                        onDeleteTask: onDeleteTask,
                      ),
                      SidebarTaskGroup(
                        title: 'Waiting for Input',
                        items: waitingTasks,
                        selectedTaskId: selectedTaskId,
                        isExpanded: groupExpanded['Waiting for Input'] ?? true,
                        onToggle: () => onToggleGroup('Waiting for Input'),
                        onTaskSelected: onTaskSelected,
                        onPinTask: onPinTask,
                        onRenameTask: onRenameTask,
                        onDeleteTask: onDeleteTask,
                      ),
                      SidebarTaskGroup(
                        title: 'In Review',
                        items: reviewTasks,
                        selectedTaskId: selectedTaskId,
                        isExpanded: groupExpanded['In Review'] ?? false,
                        onToggle: () => onToggleGroup('In Review'),
                        onTaskSelected: onTaskSelected,
                        onPinTask: onPinTask,
                        onRenameTask: onRenameTask,
                        onDeleteTask: onDeleteTask,
                      ),
                      SidebarTaskGroup(
                        title: 'Completed',
                        items: completedTasks,
                        selectedTaskId: selectedTaskId,
                        isExpanded: groupExpanded['Completed'] ?? false,
                        onToggle: () => onToggleGroup('Completed'),
                        onTaskSelected: onTaskSelected,
                        onPinTask: onPinTask,
                        onRenameTask: onRenameTask,
                        onDeleteTask: onDeleteTask,
                      ),
                      SidebarTaskGroup(
                        title: 'Failed',
                        items: failedTasks,
                        selectedTaskId: selectedTaskId,
                        isExpanded: groupExpanded['Failed'] ?? false,
                        onToggle: () => onToggleGroup('Failed'),
                        onTaskSelected: onTaskSelected,
                        onPinTask: onPinTask,
                        onRenameTask: onRenameTask,
                        onDeleteTask: onDeleteTask,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _SidebarUtilityCard(
          isSettingsSelected: isSettingsSelected,
          isUsageSelected: isUsageSelected,
          isBackendOnline: isBackendOnline,
          onOpenSettings: onOpenSettings,
          onOpenUsage: onOpenUsage,
        ),
      ],
    );
  }
}

class _SidebarUtilityCard extends StatelessWidget {
  const _SidebarUtilityCard({
    required this.isSettingsSelected,
    required this.isUsageSelected,
    required this.isBackendOnline,
    required this.onOpenSettings,
    required this.onOpenUsage,
  });

  final bool isSettingsSelected;
  final bool isUsageSelected;
  final bool isBackendOnline;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenUsage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: panelBorder),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _BackendStatusCapsule(isOnline: isBackendOnline),
          const SizedBox(width: 8),
          _UtilityActionButton(
            icon: Icons.query_stats_rounded,
            tooltip: 'Usage',
            isSelected: isUsageSelected,
            onTap: onOpenUsage,
          ),
          const SizedBox(width: 8),
          _UtilityActionButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            isSelected: isSettingsSelected,
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _BackendStatusCapsule extends StatelessWidget {
  const _BackendStatusCapsule({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final Color accent = isOnline ? successGreen : dangerRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: accent,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UtilityActionButton extends StatefulWidget {
  const _UtilityActionButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_UtilityActionButton> createState() => _UtilityActionButtonState();
}

class _UtilityActionButtonState extends State<_UtilityActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = widget.isSelected
        ? primaryBlue.withValues(alpha: 0.55)
        : _pressed
        ? primaryBlue.withValues(alpha: 0.55)
        : _hovered
        ? primaryBlue.withValues(alpha: 0.34)
        : panelBorder;
    final Color backgroundColor = widget.isSelected
        ? primaryBlue.withValues(alpha: 0.14)
        : _hovered
        ? const Color(0xFF162235)
        : _pressed
        ? primaryBlue.withValues(alpha: 0.12)
        : bubbleSurfaceAlt;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
              boxShadow: _hovered || widget.isSelected
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x180A1220),
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Icon(
              widget.icon,
              color: widget.isSelected ? textPrimary : textSecondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

class SidebarTaskGroup extends StatelessWidget {
  const SidebarTaskGroup({
    super.key,
    required this.title,
    required this.items,
    required this.selectedTaskId,
    required this.isExpanded,
    required this.onToggle,
    required this.onTaskSelected,
    required this.onPinTask,
    required this.onRenameTask,
    required this.onDeleteTask,
  });

  final String title;
  final List<TaskWorkspaceData> items;
  final String? selectedTaskId;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onTaskSelected;
  final ValueChanged<String> onPinTask;
  final ValueChanged<String> onRenameTask;
  final ValueChanged<String> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    final bool hasSelectedChild = items.any(
      (TaskWorkspaceData item) => item.task.id == selectedTaskId,
    );
    final Color headerBackground = hasSelectedChild
        ? selectionSurface
        : isExpanded
        ? const Color(0xFF101A29)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: headerBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasSelectedChild
                      ? primaryBlue.withValues(alpha: 0.36)
                      : isExpanded
                      ? panelBorder
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    color: hasSelectedChild ? primaryBlue : textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasSelectedChild ? textPrimary : textSecondary,
                        fontSize: 13,
                        fontWeight: hasSelectedChild
                            ? FontWeight.w800
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A111D),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: panelBorder),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Column(
                children: items
                    .map(
                      (TaskWorkspaceData item) => TaskListItem(
                        item: item.task,
                        isSelected: item.task.id == selectedTaskId,
                        onTap: () => onTaskSelected(item.task.id),
                        onPin: () => onPinTask(item.task.id),
                        onRename: () => onRenameTask(item.task.id),
                        onDelete: () => onDeleteTask(item.task.id),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class TaskListItem extends StatefulWidget {
  const TaskListItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onPin,
    required this.onRename,
    required this.onDelete,
  });

  final TaskItemData item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<TaskListItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color borderColor = widget.isSelected
        ? primaryBlue.withValues(alpha: 0.42)
        : Colors.transparent;
    final Color backgroundColor = widget.isSelected
        ? selectionSurface
        : _pressed
        ? const Color(0xFF141F31)
        : _hovered
        ? const Color(0xFF121D2D)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.isSelected ? primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isSelected ? textPrimary : textSecondary,
                    fontSize: 12.8,
                    fontWeight: widget.isSelected
                        ? FontWeight.w700
                        : FontWeight.w600,
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

enum _TaskCardAction { pinToTop, rename, delete }

class _TaskCardMenuItem extends StatelessWidget {
  const _TaskCardMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
