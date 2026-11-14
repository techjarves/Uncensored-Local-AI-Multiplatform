import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../models/message_model.dart';
import '../services/llm_service.dart';

class ChatBubble extends StatelessWidget {
  final MessageModel message;
  /// If true, this is the last AI message and we show speed info
  final bool showSpeed;

  const ChatBubble({super.key, required this.message, this.showSpeed = false});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isSmall = MediaQuery.of(context).size.width < 600;
    final hPad = isSmall ? 16.0 : 24.0;

    return Container(
      width: double.infinity,
      color: isUser ? Colors.transparent : context.bgMsgAi,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isUser ? context.textM : AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isUser ? Icons.person_rounded : Icons.bolt_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: _buildContent(context, isUser),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isUser) {
    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          message.content,
          style: TextStyle(
            fontSize: 15,
            color: context.text,
            height: 1.6,
          ),
        ),
      );
    }

    // AI: render markdown
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: MarkdownBody(
            data: message.content,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(fontSize: 15, color: context.text, height: 1.7),
              h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.text),
              h2: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: context.text),
              h3: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.text),
              code: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: const Color(0xFFE6EDF3),
                backgroundColor: context.isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              codeblockDecoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
              ),
              codeblockPadding: const EdgeInsets.all(14),
              blockquoteDecoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                border: const Border(
                  left: BorderSide(color: AppColors.accent, width: 3),
                ),
              ),
              blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              listBullet: TextStyle(color: context.text),
              tableHead: TextStyle(fontWeight: FontWeight.w600, color: context.text, fontSize: 14),
              tableBody: TextStyle(color: context.text, fontSize: 14),
              tableBorder: TableBorder.all(color: context.border),
              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.border)),
              ),
            ),
          ),
        ),

        // Action row: Copy + Speed
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                // Copy button
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: context.textD),
                        const SizedBox(width: 4),
                        Text('Copy', style: TextStyle(fontSize: 12, color: context.textD)),
                      ],
                    ),
                  ),
                ),

                // Speed indicator (on the last AI message)
                if (showSpeed) ...[
                  const SizedBox(width: 12),
                  Obx(() {
                    final llm = Get.find<LlmService>();
                    final speed = llm.isGenerating.value
                        ? llm.tokensPerSecond.value
                        : llm.lastGenerationSpeed.value;
                    if (speed <= 0) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded, size: 14, color: context.textD),
                        const SizedBox(width: 4),
                        Text(
                          '${speed.toStringAsFixed(1)} t/s',
                          style: TextStyle(fontSize: 12, color: context.textD),
                        ),
                      ],
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
