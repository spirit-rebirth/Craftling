import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../../core/models/assistant_section.dart';
import '../../../../core/models/chat_message.dart';
import '../../../../core/network/craftling_gateway_url.dart';
import '../../../../core/utils/assistant_parser.dart';
import '../../state/chat_controller.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage>
    with SingleTickerProviderStateMixin {
  final ChatController controller = ChatController();
  final TextEditingController inputController = TextEditingController();
  final TextEditingController serverController = TextEditingController(
    text: defaultCraftlingGatewayUrl,
  );
  final ScrollController scrollController = ScrollController();

  late final AnimationController glowController;

  @override
  void initState() {
    super.initState();
    glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    controller.dispose();
    glowController.dispose();
    inputController.dispose();
    serverController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _connect() {
    controller.connect(serverController.text);
  }

  void _sendMessage([String? text]) {
    final value = text ?? inputController.text;
    final previousCount = controller.messages.length;
    controller.sendMessage(value);
    if (controller.messages.length != previousCount) {
      inputController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = controller.messages;
    final connected = controller.connected;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFF7F0E4),
              Color(0xFFE9E3D7),
              Color(0xFFD9E6DF),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: Column(
                  children: <Widget>[
                    _buildHeroHeader(connected),
                    const SizedBox(height: 14),
                    _buildServerPanel(connected),
                    const SizedBox(height: 14),
                    Expanded(child: _buildConversationShell(messages)),
                    const SizedBox(height: 12),
                    _buildComposer(connected),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool connected) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xCCFFFCF7),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F161D),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF1C5C54), Color(0xFF2E7A70)],
              ),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Craftling Relay',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'A calmer chat surface for talking to Craftling Gateway.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF59606B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _StatusPill(connected: connected),
        ],
      ),
    );
  }

  Widget _buildServerPanel(bool connected) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xBFFAF6F0),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x1C1E2430)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Server',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Use your Craftling Gateway address. The app will connect to '
            '/__craftling__/ws automatically.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5B6471),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: serverController,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _connect(),
                  decoration: InputDecoration(
                    hintText: defaultCraftlingGatewayUrl,
                    filled: true,
                    fillColor: const Color(0xFFFDFBF8),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _connect,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1C5C54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(connected ? 'Reconnect' : 'Connect'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConversationShell(List<ChatMessage> messages) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: const Color(0xD9FFFDF9),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120D141C),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Color(0xFFF2E8D8), Color(0xFFE6EFE9)],
                ),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    'Conversation',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${messages.where((ChatMessage item) => item.role != MessageRole.system).length} messages',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF59606B),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
                      itemCount: messages.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final msg = messages[index];
                        switch (msg.role) {
                          case MessageRole.user:
                            return _userBubble(msg);
                          case MessageRole.assistant:
                            return _assistantBubble(msg);
                          case MessageRole.system:
                            return _systemMessage(msg);
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFE6EFE9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 36,
                color: Color(0xFF1C5C54),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Start with a clean connection.',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to your backend, then send a message. Thinking state appears instantly and resolves into the final reply in place.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5B6471),
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userBubble(ChatMessage message) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(26),
              topRight: Radius.circular(26),
              bottomLeft: Radius.circular(26),
              bottomRight: Radius.circular(10),
            ),
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF1C5C54), Color(0xFF2C7B72)],
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x221C5C54),
                blurRadius: 20,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _assistantBubble(ChatMessage message) {
    final sections = parseAssistantSections(message.content);

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FadeTransition(
            opacity: Tween<double>(begin: 0.65, end: 1).animate(glowController),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFC66A3D), Color(0xFFDB8A58)],
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: message.isPending
                      ? const Color(0xFFF5EFE6)
                      : const Color(0xFFFFFCF8),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(26),
                    bottomLeft: Radius.circular(26),
                    bottomRight: Radius.circular(26),
                  ),
                  border: Border.all(
                    color: message.isPending
                        ? const Color(0x33C66A3D)
                        : const Color(0x1E1E2430),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: message.isPending && message.content.trim().isEmpty
                      ? _ThinkingBubble(content: message.content)
                      : _AssistantMessageBody(
                          key: const ValueKey<String>('assistant::'),
                          sections: sections,
                          styleSheet: buildAssistantMarkdownStyleSheet(context),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemMessage(ChatMessage message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF2ECE3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF6B6F76),
            fontSize: 12.5,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildComposer(bool connected) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xD9FFFDF9),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120D141C),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: inputController,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: _sendMessage,
              decoration: InputDecoration(
                hintText: connected
                    ? 'Send a message to OpenClaw...'
                    : 'Connect to Craftling Gateway first...',
                filled: true,
                fillColor: const Color(0xFFF7F3ED),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: connected
                    ? const <Color>[Color(0xFFC66A3D), Color(0xFFD98956)]
                    : const <Color>[Color(0xFFA7A09A), Color(0xFFBBB4AD)],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x22C66A3D),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: IconButton(
              onPressed: connected ? _sendMessage : null,
              icon: const Icon(Icons.arrow_upward_rounded),
              color: Colors.white,
              iconSize: 22,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final Color background = connected
        ? const Color(0xFFE2F1EA)
        : const Color(0xFFF0E7DE);
    final Color dotColor = connected
        ? const Color(0xFF2C7B72)
        : const Color(0xFFC66A3D);
    final String label = connected ? 'Live link' : 'Offline';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF202631),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantMessageBody extends StatelessWidget {
  const _AssistantMessageBody({
    super.key,
    required this.sections,
    required this.styleSheet,
  });

  final List<AssistantSection> sections;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(sections.length, (int index) {
        final section = sections[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == sections.length - 1 ? 0 : 14,
          ),
          child: _AssistantSectionCard(
            section: section,
            styleSheet: styleSheet,
          ),
        );
      }),
    );
  }
}

class _AssistantSectionCard extends StatelessWidget {
  const _AssistantSectionCard({
    required this.section,
    required this.styleSheet,
  });

  final AssistantSection section;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    final meta = section.meta;
    final body = section.body.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: meta == null ? Colors.transparent : const Color(0xFFF9F2E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: meta == null ? Colors.transparent : const Color(0x22C66A3D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (meta != null) ...<Widget>[
            _MetaHeader(meta: meta),
            if (body.isNotEmpty) const SizedBox(height: 12),
          ],
          if (body.isNotEmpty)
            MarkdownBody(
              data: body,
              selectable: true,
              shrinkWrap: true,
              styleSheet: styleSheet,
              softLineBreak: true,
            ),
        ],
      ),
    );
  }
}

class _MetaHeader extends StatelessWidget {
  const _MetaHeader({required this.meta});

  final ReplyMeta meta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE0CF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x44C66A3D)),
              ),
              child: const Text(
                'Stage',
                style: TextStyle(
                  color: Color(0xFF9B4B26),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  meta.stage,
                  style: const TextStyle(
                    color: Color(0xFF212834),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _MetaChip(
              label: 'Skill',
              value: meta.skill,
              backgroundColor: const Color(0xFFE3F1EB),
              borderColor: const Color(0x332C7B72),
              labelColor: const Color(0xFF2C7B72),
            ),
            _MetaChip(
              label: 'Tool',
              value: meta.tool,
              backgroundColor: const Color(0xFFF5E8D8),
              borderColor: const Color(0x33C66A3D),
              labelColor: const Color(0xFF9B5C39),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.value,
    required this.backgroundColor,
    required this.borderColor,
    required this.labelColor,
  });

  final String label;
  final String value;
  final Color backgroundColor;
  final Color borderColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Color(0xFF4D5A6B),
            fontSize: 12.5,
            height: 1.35,
          ),
          children: <InlineSpan>[
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: labelColor, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFF212834),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey<String>('thinking:$content'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _PulsingDots(),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            content.isEmpty ? 'OpenClaw is shaping a reply...' : content,
            style: const TextStyle(
              color: Color(0xFF5D534B),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int index) {
            final double phase = (controller.value - index * 0.16).clamp(
              0.0,
              1.0,
            );
            final double opacity =
                0.35 + ((1 - (phase - 0.5).abs() * 2) * 0.65);
            return Container(
              margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(
                  0xFFC66A3D,
                ).withValues(alpha: opacity.clamp(0.25, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
