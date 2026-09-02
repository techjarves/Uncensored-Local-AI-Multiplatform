import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../theme/app_colors.dart';
import '../models/ai_model_info.dart';
import '../models/download_state.dart';

class ModelCard extends StatelessWidget {
  final AiModelInfo model;
  final bool isDownloaded;
  final bool isCurrentlyDownloading;
  final DownloadState? downloadState;
  final bool isLoaded;
  final bool isLoadingModel;
  final String loadingStatusMsg;
  final double loadingProgress;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;
  final VoidCallback onLoad;
  final VoidCallback onDelete;
  final VoidCallback? onRemoveCustom;
  final VoidCallback? onCancelLoad;
  final VoidCallback? onUnload;

  const ModelCard({
    super.key,
    required this.model,
    required this.isDownloaded,
    required this.isCurrentlyDownloading,
    this.downloadState,
    required this.isLoaded,
    required this.isLoadingModel,
    this.loadingStatusMsg = '',
    this.loadingProgress = 0.0,
    required this.onDownload,
    required this.onCancelDownload,
    required this.onLoad,
    required this.onDelete,
    this.onRemoveCustom,
    this.onCancelLoad,
    this.onUnload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isLoaded ? AppColors.accent.withValues(alpha: 0.05) : context.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLoaded
              ? AppColors.accent.withValues(alpha: 0.5)
              : isLoadingModel
                  ? AppColors.orange.withValues(alpha: 0.5)
                  : isCurrentlyDownloading
                      ? AppColors.orange.withValues(alpha: 0.4)
                      : context.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _labelBadge(model.label, model.isUncensored),
                if (model.badge.isNotEmpty)
                  _accentBadge(model.badge),
                if (isLoaded) _statusBadge('LOADED', AppColors.green, Icons.check_circle),
                if (isLoadingModel)
                  _statusBadge('LOADING', AppColors.orange, Icons.hourglass_top_rounded),
                if (isCurrentlyDownloading)
                  _statusBadge('DOWNLOADING', AppColors.orange, Icons.downloading_rounded),
              ],
            ),

            const SizedBox(height: 12),

            // ── Model name ────────────────────────────────────────
            Text(
              model.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.text,
              ),
            ),

            const SizedBox(height: 6),

            // ── Size and RAM ──────────────────────────────────────
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storage_rounded, size: 14, color: context.textD),
                    const SizedBox(width: 4),
                    Text('${model.sizeGb} GB',
                        style: TextStyle(fontSize: 12, color: context.textM)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.memory_rounded, size: 14, color: context.textD),
                    const SizedBox(width: 4),
                    Text('Min ${model.minRamGb} GB RAM',
                        style: TextStyle(fontSize: 12, color: context.textM)),
                  ],
                ),
                if (isDownloaded && !isCurrentlyDownloading)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: AppColors.green),
                      SizedBox(width: 4),
                      Text('Downloaded',
                          style: TextStyle(fontSize: 12, color: AppColors.green)),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Loading progress ──────────────────────────────────
            if (isLoadingModel) ...[
              _buildLoadingProgress(context),
              const SizedBox(height: 16),
            ],

            // ── Download progress with realtime stats ─────────────
            if (isCurrentlyDownloading && downloadState != null) ...[
              _buildDownloadProgress(context, downloadState!),
              const SizedBox(height: 16),
            ],

            // ── Action buttons ────────────────────────────────────
            if (!isCurrentlyDownloading && !isLoadingModel) _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingProgress(BuildContext context) {
    final percent = (loadingProgress * 100).clamp(0, 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        LinearPercentIndicator(
          lineHeight: 6,
          percent: loadingProgress.clamp(0.0, 1.0),
          backgroundColor: context.border,
          linearGradient: const LinearGradient(
            colors: [AppColors.orange, AppColors.accent],
          ),
          barRadius: const Radius.circular(3),
          padding: EdgeInsets.zero,
          animation: false,
        ),
        const SizedBox(height: 10),

        // Status row
        Row(
          children: [
            // Percentage
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.orange,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Status message
            Expanded(
              child: Text(
                loadingStatusMsg.isNotEmpty ? loadingStatusMsg : 'Loading...',
                style: TextStyle(fontSize: 12, color: context.textM),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Cancel button
            if (onCancelLoad != null)
              TextButton.icon(
                onPressed: onCancelLoad,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('Stop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadProgress(BuildContext context, DownloadState ds) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        LinearPercentIndicator(
          lineHeight: 6,
          percent: ds.progress,
          backgroundColor: context.border,
          linearGradient: const LinearGradient(
            colors: [AppColors.accent, Color(0xFF8B5CF6)],
          ),
          barRadius: const Radius.circular(3),
          padding: EdgeInsets.zero,
          animation: false,
        ),
        const SizedBox(height: 8),

        // Stats row
        Row(
          children: [
            Text(
              '${ds.percent.toStringAsFixed(1)}%',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accentHi),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '⚡ ${ds.speedStr}',
                style: const TextStyle(fontSize: 11, color: AppColors.accentHi),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onCancelDownload,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Cancel', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Stats detail row
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '${ds.downloadedStr} / ${ds.totalStr}',
              style: TextStyle(fontSize: 11, color: context.textM),
            ),
            Text(
              '${ds.remainingStr} left',
              style: TextStyle(fontSize: 11, color: context.textD),
            ),
            if (ds.speedBytesPerSec > 0)
              Text(
                'ETA: ${ds.etaStr}',
                style: TextStyle(fontSize: 11, color: context.textD),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    // If it's a custom model, we show the red remove icon.
    // We use it instead of the regular 'delete file' if it's downloaded.
    final Widget removeIcon = IconButton(
      onPressed: onRemoveCustom,
      icon: const Icon(Icons.remove_circle_outline, size: 20),
      color: AppColors.red,
      tooltip: 'Remove from library',
    );

    return Row(
      children: [
        if (!isDownloaded) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text('Download (${model.sizeGb} GB)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.isDark ? context.text : AppColors.accent,
                foregroundColor: context.isDark ? context.bg : Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (model.isCustom && onRemoveCustom != null) ...[
            const SizedBox(width: 8),
            removeIcon,
          ],
        ],

        if (isDownloaded && !isLoaded) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Load Model'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (model.isCustom && onRemoveCustom != null)
            removeIcon
          else
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: context.textD,
              tooltip: 'Delete model file',
            ),
        ],

        if (isDownloaded && isLoaded) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.green),
              label: const Text('Active', style: TextStyle(color: AppColors.green)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.green),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Unload button
          if (onUnload != null)
            Tooltip(
              message: 'Unload model from memory',
              child: Material(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onUnload,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.eject_rounded, size: 20, color: AppColors.orange),
                  ),
                ),
              ),
            ),
          if (model.isCustom && onRemoveCustom != null) ...[
            const SizedBox(width: 8),
            removeIcon,
          ],
        ],
      ],
    );
  }

  Widget _labelBadge(String label, bool isUncensored) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUncensored
            ? AppColors.uncensored.withValues(alpha: 0.15)
            : AppColors.standard.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isUncensored ? AppColors.uncensored : AppColors.standard,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _accentBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.accentHi,
        ),
      ),
    );
  }

  Widget _statusBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
