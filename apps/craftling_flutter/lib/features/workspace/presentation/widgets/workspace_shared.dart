import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import '../theme/workspace_colors.dart';

class PanelShell extends StatelessWidget {
  const PanelShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: panelBackground,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: panelBorder),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 22,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AgentIdentityRow extends StatelessWidget {
  const AgentIdentityRow({
    super.key,
    required this.label,
    required this.chipLabel,
    this.chipColor = primaryBlue,
  });

  final String label;
  final String chipLabel;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF223453),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: textPrimary,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: chipColor.withValues(alpha: 0.45)),
          ),
          child: Text(
            chipLabel,
            style: TextStyle(
              color: chipColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class EvidenceTypeBadge extends StatelessWidget {
  const EvidenceTypeBadge({super.key, required this.type});

  final EvidenceType type;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (type) {
      EvidenceType.log => primaryBlue,
      EvidenceType.validation => successGreen,
      EvidenceType.toolOutput => warningAmber,
      EvidenceType.screenshot => const Color(0xFF74A8FF),
      EvidenceType.video => const Color(0xFF9B88FF),
      EvidenceType.note => textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        evidenceTypeLabel(type),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String phaseLabel(TaskPhase phase) {
  return switch (phase) {
    TaskPhase.request => 'Request',
    TaskPhase.plan => 'Plan',
    TaskPhase.dispatch => 'Dispatch',
    TaskPhase.run => 'Run',
    TaskPhase.merge => 'Merge',
    TaskPhase.review => 'Review',
  };
}

String statusLabel(TaskStatus status) {
  return switch (status) {
    TaskStatus.running => 'Running',
    TaskStatus.waitingForInput => 'Waiting for Input',
    TaskStatus.pending => 'Pending',
    TaskStatus.done => 'Done',
    TaskStatus.failed => 'Failed',
  };
}

Color statusColor(TaskStatus status) {
  return switch (status) {
    TaskStatus.running => primaryBlue,
    TaskStatus.waitingForInput => warningAmber,
    TaskStatus.pending => const Color(0xFF7FA1FF),
    TaskStatus.done => successGreen,
    TaskStatus.failed => dangerRed,
  };
}

String evidenceTypeLabel(EvidenceType type) {
  return switch (type) {
    EvidenceType.log => 'Log',
    EvidenceType.validation => 'Validation',
    EvidenceType.toolOutput => 'Tool Output',
    EvidenceType.screenshot => 'Screenshot',
    EvidenceType.video => 'Video',
    EvidenceType.note => 'Note',
  };
}
