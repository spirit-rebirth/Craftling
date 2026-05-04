import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import '../theme/workspace_colors.dart';
import 'workspace_shared.dart';

class TaskDetailsSidebar extends StatefulWidget {
  const TaskDetailsSidebar({super.key, required this.selectedTask});

  final TaskWorkspaceData? selectedTask;

  @override
  State<TaskDetailsSidebar> createState() => _TaskDetailsSidebarState();
}

class _TaskDetailsSidebarState extends State<TaskDetailsSidebar> {
  final Map<String, String> _priorityByTaskId = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final TaskWorkspaceData? selectedTask = widget.selectedTask;
    if (selectedTask == null) {
      return const PanelShell(child: _EmptyDetailsState());
    }

    final String priority =
        _priorityByTaskId[selectedTask.task.id] ??
        _overviewValue(selectedTask.overviewRows, 'Priority') ??
        'Normal';

    return PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Task Details',
            style: TextStyle(
              color: textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          OverviewSection(
            rows: selectedTask.overviewRows,
            priority: priority,
            onPriorityChanged: (String nextPriority) {
              setState(() {
                _priorityByTaskId[selectedTask.task.id] = nextPriority;
              });
            },
          ),
          const SizedBox(height: 18),
          Expanded(
            child: EvidenceSection(evidenceItems: selectedTask.evidence),
          ),
        ],
      ),
    );
  }

  String? _overviewValue(List<MapEntry<String, String>> rows, String key) {
    for (final MapEntry<String, String> row in rows) {
      if (row.key == key) {
        return row.value;
      }
    }
    return null;
  }
}

class _EmptyDetailsState extends StatelessWidget {
  const _EmptyDetailsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Icon(
              Icons.dashboard_customize_outlined,
              color: textSecondary,
              size: 32,
            ),
            SizedBox(height: 14),
            Text(
              'Task details will appear here once a task is created.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary, fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class OverviewSection extends StatelessWidget {
  const OverviewSection({
    super.key,
    required this.rows,
    required this.priority,
    required this.onPriorityChanged,
  });

  final List<MapEntry<String, String>> rows;
  final String priority;
  final ValueChanged<String> onPriorityChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _DetailsSectionHeader(
          icon: Icons.tune_rounded,
          title: 'Overview',
        ),
        const SizedBox(height: 12),
        ...rows.map((MapEntry<String, String> row) {
          if (row.key == 'Priority') {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PriorityOverviewRow(
                value: priority,
                onChanged: onPriorityChanged,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OverviewInfoRow(label: row.key, value: row.value),
          );
        }),
      ],
    );
  }
}

class OverviewInfoRow extends StatelessWidget {
  const OverviewInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: panelBorder),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 94,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PriorityOverviewRow extends StatelessWidget {
  const PriorityOverviewRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> priorities = <String>['High', 'Normal', 'Low'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryBlue.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 94,
            child: Text(
              'Priority',
              style: TextStyle(
                color: mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Set priority',
              onSelected: onChanged,
              color: const Color(0xFF101825),
              surfaceTintColor: Colors.transparent,
              offset: const Offset(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: panelBorder),
              ),
              itemBuilder: (BuildContext context) => priorities
                  .map(
                    (String priority) => PopupMenuItem<String>(
                      value: priority,
                      child: Row(
                        children: <Widget>[
                          Icon(
                            priority == value
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: priority == value ? primaryBlue : mutedText,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            priority,
                            style: const TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: primaryBlue.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: textSecondary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EvidenceSection extends StatelessWidget {
  const EvidenceSection({super.key, required this.evidenceItems});

  final List<EvidenceItemData> evidenceItems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _DetailsSectionHeader(
          icon: Icons.fact_check_rounded,
          title: 'Evidence',
        ),
        const SizedBox(height: 12),
        Expanded(
          child: evidenceItems.isEmpty
              ? const _EmptyEvidenceList()
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: evidenceItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final EvidenceItemData item = evidenceItems[index];
                    return EvidenceListItem(
                      key: ValueKey<String>(
                        item.id.isNotEmpty
                            ? item.id
                            : '${item.title}:${item.assetPath ?? item.source}',
                      ),
                      item: item,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DetailsSectionHeader extends StatelessWidget {
  const _DetailsSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: primaryBlue.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: primaryBlue.withValues(alpha: 0.26)),
          ),
          child: Icon(icon, color: primaryBlue, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _EmptyEvidenceList extends StatelessWidget {
  const _EmptyEvidenceList();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: panelBorder),
      ),
      child: const Text(
        'Evidence will appear here after validation steps complete.',
        textAlign: TextAlign.center,
        style: TextStyle(color: mutedText, fontSize: 13, height: 1.4),
      ),
    );
  }
}

class EvidenceListItem extends StatelessWidget {
  const EvidenceListItem({super.key, required this.item});

  final EvidenceItemData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: panelBorder.withValues(alpha: 0.72)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: primaryBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryBlue.withValues(alpha: 0.18)),
            ),
            child: Icon(
              _evidenceIcon(item.type),
              color: textSecondary,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.stage ?? item.timeAgo,
                      style: const TextStyle(
                        color: mutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.text != null && item.text!.trim().isNotEmpty
                      ? item.text!
                      : item.source,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                if (item.assetPath != null && item.assetPath!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  _EvidencePreview(path: item.assetPath!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _evidenceIcon(EvidenceType type) {
    return switch (type) {
      EvidenceType.log => Icons.terminal_rounded,
      EvidenceType.validation => Icons.verified_rounded,
      EvidenceType.toolOutput => Icons.build_circle_outlined,
      EvidenceType.screenshot => Icons.image_outlined,
      EvidenceType.video => Icons.play_circle_outline_rounded,
      EvidenceType.note => Icons.sticky_note_2_outlined,
    };
  }
}

class _EvidencePreview extends StatefulWidget {
  const _EvidencePreview({required this.path});

  final String path;

  @override
  State<_EvidencePreview> createState() => _EvidencePreviewState();
}

class _EvidencePreviewState extends State<_EvidencePreview> {
  Uint8List? _dataImageBytes;
  bool _invalidDataImage = false;

  bool get _isDataImage => widget.path.startsWith('data:image/');

  bool get _isNetworkImage =>
      widget.path.startsWith('http://') || widget.path.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  @override
  void didUpdateWidget(covariant _EvidencePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _prepareImage();
    }
  }

  void _prepareImage() {
    _dataImageBytes = null;
    _invalidDataImage = false;
    if (!_isDataImage) {
      return;
    }

    final int separatorIndex = widget.path.indexOf(',');
    if (separatorIndex <= 0 ||
        !widget.path.substring(0, separatorIndex).toLowerCase().contains(';base64')) {
      _invalidDataImage = true;
      return;
    }

    try {
      _dataImageBytes = base64Decode(widget.path.substring(separatorIndex + 1));
    } on FormatException {
      _invalidDataImage = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invalidDataImage || (!_isDataImage && !_isNetworkImage)) {
      return _PathPreview(path: widget.path);
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openPreviewDialog(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: <Widget>[
                _buildImage(height: 96, fit: BoxFit.cover),
                Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage({required BoxFit fit, double? height, double? width = double.infinity}) {
    final Uint8List? bytes = _dataImageBytes;
    if (_isDataImage && bytes != null) {
      return Image.memory(
        bytes,
        height: height,
        width: width,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _PathPreview(path: widget.path),
      );
    }

    if (_isNetworkImage) {
      return Image.network(
        widget.path,
        height: height,
        width: width,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _PathPreview(path: widget.path),
      );
    }

    return _PathPreview(path: widget.path);
  }

  void _openPreviewDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: _buildImage(fit: BoxFit.contain, width: null),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white,
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PathPreview extends StatelessWidget {
  const _PathPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bubbleSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: panelBorder),
      ),
      child: SelectableText(
        path,
        maxLines: 3,
        style: const TextStyle(color: mutedText, fontSize: 11.5, height: 1.3),
      ),
    );
  }
}
