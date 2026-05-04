import 'package:flutter/material.dart';

import '../../../workspace/domain/workspace_models.dart';
import '../../../workspace/presentation/theme/workspace_colors.dart';
import '../../../workspace/presentation/widgets/workspace_shared.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DashboardContent(
            activeTasks: const <TaskWorkspaceData>[],
            attentionTasks: const <TaskWorkspaceData>[],
            onOpenTask: (_) {},
            onApproveTask: (_) {},
            onOpenTasks: () {},
            onOpenInbox: () {},
            onOpenAgents: () {},
            onOpenWorkspace: () {},
          ),
        ),
      ),
    );
  }
}

class DashboardContent extends StatelessWidget {
  const DashboardContent({
    super.key,
    required this.activeTasks,
    required this.attentionTasks,
    required this.onOpenTask,
    required this.onApproveTask,
    required this.onOpenTasks,
    required this.onOpenInbox,
    required this.onOpenAgents,
    required this.onOpenWorkspace,
  });

  final List<TaskWorkspaceData> activeTasks;
  final List<TaskWorkspaceData> attentionTasks;
  final ValueChanged<String> onOpenTask;
  final ValueChanged<String> onApproveTask;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenAgents;
  final VoidCallback onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Good afternoon, Alex',
            style: TextStyle(
              color: textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'You have ${attentionTasks.length} approvals waiting and ${activeTasks.length} active tasks.',
            style: const TextStyle(
              color: textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          GridView.count(
            crossAxisCount: 4,
            childAspectRatio: 1.0,
            shrinkWrap: true,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            physics: const NeverScrollableScrollPhysics(),
            children: <Widget>[
              DashboardFeatureCard(
                icon: Icons.task_alt_rounded,
                title: 'Tasks',
                description: 'Create, track, and manage AI tasks.',
                ctaLabel: 'New Task',
                accentColor: primaryBlue,
                isPrimary: true,
                onTap: onOpenTasks,
              ),
              DashboardFeatureCard(
                icon: Icons.inbox_rounded,
                title: 'Inbox',
                description: 'Review approvals, replies, and agent updates.',
                ctaLabel: 'Open Inbox',
                accentColor: const Color(0xFF4FBFEF),
                onTap: onOpenInbox,
              ),
              DashboardFeatureCard(
                icon: Icons.smart_toy_rounded,
                title: 'Agents',
                description: 'Manage AI personas and future digital workers.',
                ctaLabel: 'Open Agents',
                accentColor: const Color(0xFF45D7E8),
                onTap: onOpenAgents,
              ),
              DashboardFeatureCard(
                icon: Icons.view_quilt_rounded,
                title: 'Workspace',
                description: 'Organization, versioning, and collaboration.',
                ctaLabel: 'Open Workspace',
                accentColor: const Color(0xFF7D8DFF),
                onTap: onOpenWorkspace,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ActiveTasksPanel(
                    tasks: activeTasks,
                    onOpenTask: onOpenTask,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: NeedsAttentionPanel(
                    tasks: attentionTasks,
                    onOpenTask: onOpenTask,
                    onApproveTask: onApproveTask,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardFeatureCard extends StatefulWidget {
  const DashboardFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.accentColor,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String ctaLabel;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  State<DashboardFeatureCard> createState() => _DashboardFeatureCardState();
}

class _DashboardFeatureCardState extends State<DashboardFeatureCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Color backgroundStart = Color.lerp(
      const Color(0xFF172A43),
      widget.accentColor,
      widget.isPrimary ? (_hovered ? 0.28 : 0.22) : (_hovered ? 0.20 : 0.14),
    )!;
    final Color backgroundMiddle = Color.lerp(
      const Color(0xFF101C2E),
      widget.accentColor,
      widget.isPrimary ? 0.10 : 0.06,
    )!;
    final Color backgroundEnd = Color.lerp(
      const Color(0xFF07111F),
      widget.accentColor,
      widget.isPrimary ? 0.08 : 0.04,
    )!;
    final Color borderColor = widget.accentColor.withValues(
      alpha: _hovered ? 0.42 : 0.22,
    );
    final List<BoxShadow> shadows = <BoxShadow>[
      BoxShadow(
        color: const Color(
          0xFF000000,
        ).withValues(alpha: _pressed ? 0.20 : 0.34),
        blurRadius: _hovered ? 26 : 18,
        offset: Offset(0, _pressed ? 8 : 14),
      ),
      BoxShadow(
        color: widget.accentColor.withValues(
          alpha: widget.isPrimary
              ? (_hovered ? 0.24 : 0.15)
              : (_hovered ? 0.16 : 0.09),
        ),
        blurRadius: _hovered ? 30 : 20,
        offset: const Offset(0, 12),
      ),
    ];

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
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: Offset(0, _pressed ? 0.006 : (_hovered ? -0.018 : 0)),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.985 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor),
                boxShadow: shadows,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              backgroundStart,
                              backgroundMiddle,
                              backgroundEnd,
                            ],
                          ),
                        ),
                      ),
                    ),
                    _DashboardFeaturePattern(accentColor: widget.accentColor),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: _hovered ? 0.09 : 0.045,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _FeatureIconBadge(
                            icon: widget.icon,
                            accentColor: widget.accentColor,
                            isPrimary: widget.isPrimary,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 13.5,
                              height: 1.42,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          _FeatureCtaRow(
                            label: widget.ctaLabel,
                            accentColor: widget.accentColor,
                            highlighted: _hovered || widget.isPrimary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardFeaturePattern extends StatelessWidget {
  const _DashboardFeaturePattern({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -34,
              top: -18,
              child: Transform.rotate(
                angle: -0.42,
                child: Container(
                  width: 140,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.075),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 96,
              bottom: 62,
              child: Transform.rotate(
                angle: -0.52,
                child: Container(
                  width: 150,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: 72,
              child: Transform.rotate(
                angle: 0.72,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureIconBadge extends StatelessWidget {
  const _FeatureIconBadge({
    required this.icon,
    required this.accentColor,
    required this.isPrimary,
  });

  final IconData icon;
  final Color accentColor;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(const Color(0xFF27456D), accentColor, 0.34)!,
            Color.lerp(const Color(0xFF13233B), accentColor, 0.18)!,
          ],
        ),
        border: Border.all(color: accentColor.withValues(alpha: 0.34)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accentColor.withValues(alpha: isPrimary ? 0.24 : 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: textPrimary, size: 26),
    );
  }
}

class _FeatureCtaRow extends StatelessWidget {
  const _FeatureCtaRow({
    required this.label,
    required this.accentColor,
    required this.highlighted,
  });

  final String label;
  final Color accentColor;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: Color.lerp(
          const Color(0xFF17243A),
          accentColor,
          highlighted ? 0.18 : 0.10,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: highlighted ? 0.34 : 0.18),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            color: highlighted ? accentColor : textSecondary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class ActiveTasksPanel extends StatelessWidget {
  const ActiveTasksPanel({
    super.key,
    required this.tasks,
    required this.onOpenTask,
  });

  final List<TaskWorkspaceData> tasks;
  final ValueChanged<String> onOpenTask;

  @override
  Widget build(BuildContext context) {
    return _DashboardPanel(
      title: 'Active Tasks',
      child: tasks.isEmpty
          ? const _DashboardEmptyList(message: 'No tasks are running.')
          : ListView.separated(
              itemCount: tasks.length,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final TaskWorkspaceData item = tasks[index];
                return _ActiveTaskRow(
                  task: item,
                  onTap: () => onOpenTask(item.task.id),
                );
              },
            ),
    );
  }
}

class NeedsAttentionPanel extends StatelessWidget {
  const NeedsAttentionPanel({
    super.key,
    required this.tasks,
    required this.onOpenTask,
    required this.onApproveTask,
  });

  final List<TaskWorkspaceData> tasks;
  final ValueChanged<String> onOpenTask;
  final ValueChanged<String> onApproveTask;

  @override
  Widget build(BuildContext context) {
    return _DashboardPanel(
      title: 'Needs Attention',
      child: tasks.isEmpty
          ? const _DashboardEmptyList(message: 'No tasks need approval.')
          : ListView.separated(
              itemCount: tasks.length,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final TaskWorkspaceData item = tasks[index];
                return _AttentionRow(
                  task: item,
                  onOpen: () => onOpenTask(item.task.id),
                  onApprove: () => onApproveTask(item.task.id),
                );
              },
            ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DashboardEmptyList extends StatelessWidget {
  const _DashboardEmptyList({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: mutedText, fontSize: 13.5, height: 1.4),
      ),
    );
  }
}

class _ActiveTaskRow extends StatefulWidget {
  const _ActiveTaskRow({required this.task, required this.onTap});

  final TaskWorkspaceData task;
  final VoidCallback onTap;

  @override
  State<_ActiveTaskRow> createState() => _ActiveTaskRowState();
}

class _ActiveTaskRowState extends State<_ActiveTaskRow> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            _pressed ? 1 : (_hovered ? -2 : 0),
            0,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? panelBackgroundAlt : panelBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? primaryBlue.withValues(alpha: 0.36)
                  : panelBorder,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.task.task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.task.summaryLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: mutedText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusBadge(
                label: statusLabel(widget.task.task.status),
                color: statusColor(widget.task.task.status),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({
    required this.task,
    required this.onOpen,
    required this.onApprove,
  });

  final TaskWorkspaceData task;
  final VoidCallback onOpen;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: panelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const StatusBadge(label: 'Approval Required', color: successGreen),
          const SizedBox(height: 12),
          Text(
            task.task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task.summaryLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: successGreen,
                  foregroundColor: pageBackground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Approve'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: onOpen,
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  side: const BorderSide(color: panelBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
