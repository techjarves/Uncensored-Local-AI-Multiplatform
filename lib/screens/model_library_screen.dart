import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../controllers/model_controller.dart';
import '../services/model_manager.dart';
import '../models/ai_model_info.dart';
import '../widgets/model_card.dart';

class ModelLibraryScreen extends StatelessWidget {
  final bool embedded;
  const ModelLibraryScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return _ModelLibraryBody(showBackButton: false);
    }
    return Scaffold(
      backgroundColor: context.bg,
      body: _ModelLibraryBody(showBackButton: true),
    );
  }
}

enum _Filter { all, downloaded, uncensored, custom }

class _ModelLibraryBody extends StatefulWidget {
  final bool showBackButton;
  const _ModelLibraryBody({this.showBackButton = false});

  @override
  State<_ModelLibraryBody> createState() => _ModelLibraryBodyState();
}

class _ModelLibraryBodyState extends State<_ModelLibraryBody> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<ModelController>();
    final manager = Get.find<ModelManager>();

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────
        Container(
          padding: EdgeInsets.only(
            top: widget.showBackButton ? MediaQuery.of(context).padding.top : 0,
            left: 4,
            right: 4,
          ),
          decoration: BoxDecoration(
            color: context.bg,
            border: Border(
              bottom: BorderSide(color: context.border, width: 0.5),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (widget.showBackButton)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                if (!widget.showBackButton) const SizedBox(width: 12),
                Text(
                  'Models',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
                const Spacer(),
                _ImportButton(ctrl: ctrl),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),

        // ── Filter chips ─────────────────────────────
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, 'All', _Filter.all),
              _chip(context, 'Downloaded', _Filter.downloaded),
              _chip(context, 'Uncensored', _Filter.uncensored),
              _chip(context, 'Custom', _Filter.custom),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────
        Expanded(
          child: Obx(() {
            final allCatalog = ctrl.catalog.toList();
            final downloaded = manager.downloadedModels.toList();
            final _ = manager.activeDownloads.length;
            // ignore: unused_local_variable
            final tick = manager.tick.value;

            // Apply filter
            List<AiModelInfo> filtered;
            switch (_filter) {
              case _Filter.downloaded:
                filtered = allCatalog
                    .where((m) => downloaded.contains(m.filename))
                    .toList();
                break;
              case _Filter.uncensored:
                filtered = allCatalog.where((m) => m.isUncensored).toList();
                break;
              case _Filter.custom:
                filtered = allCatalog.where((m) => m.isCustom).toList();
                break;
              case _Filter.all:
                filtered = allCatalog;
            }

            // Always sort the active model to the top if it's in the filtered list
            final activeFilename = ctrl.selectedModelFilename.value;
            if (activeFilename != null) {
              filtered.sort((a, b) {
                if (a.filename == activeFilename) return -1;
                if (b.filename == activeFilename) return 1;
                return 0; // maintain relative order for the rest
              });
            }

            if (allCatalog.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.widgets_outlined,
                      size: 48,
                      color: context.textD,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No models in catalog.',
                      style: TextStyle(color: context.textD, fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            if (filtered.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_off_rounded,
                      size: 40,
                      color: context.textD,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No models match this filter.',
                      style: TextStyle(color: context.textD, fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // ── Local files not in catalog ──────────
                if (_filter == _Filter.all ||
                    _filter == _Filter.downloaded) ...[
                  ...downloaded
                      .where((f) => !allCatalog.any((m) => m.filename == f))
                      .map((f) => _localFileCard(context, ctrl, f)),
                ],

                // ── Count ───────────────────────────────
                _sectionTitle(
                  context,
                  '${_filter == _Filter.all ? "Available" : _filter.name[0].toUpperCase() + _filter.name.substring(1)} Models (${filtered.length})',
                ),
                const SizedBox(height: 12),

                // ── Model cards ─────────────────────────
                ...List.generate(filtered.length, (index) {
                  final model = filtered[index];
                  final isDl = downloaded.contains(model.filename);
                  final isActiveDownload = manager.isDownloading(
                    model.filename,
                  );
                  final dlState = manager.getDownloadState(model.filename);

                  return Column(
                    children: [
                      ModelCard(
                        model: model,
                        isDownloaded: isDl,
                        isCurrentlyDownloading: isActiveDownload,
                        downloadState: dlState,
                        isLoaded:
                            ctrl.selectedModelFilename.value ==
                                model.filename &&
                            ctrl.isModelLoaded,
                        isLoadingModel:
                            ctrl.loadingModelFilename.value == model.filename,
                        loadingStatusMsg: ctrl.loadingStatusMsg.value,
                        loadingProgress: ctrl.loadingProgress.value,
                        onDownload: () => ctrl.downloadModel(model),
                        onCancelDownload: () =>
                            ctrl.cancelDownload(model.filename),
                        onLoad: () => ctrl.loadModel(model.filename),
                        onDelete: () => _confirmDelete(context, ctrl, model),
                        onRemoveCustom: () =>
                            _confirmRemoveCustom(context, ctrl, model),
                        onCancelLoad: () => ctrl.cancelLoadModel(),
                        onUnload: () => ctrl.unloadCurrentModel(),
                      ),
                    ],
                  ).animate().fadeIn(
                    delay: Duration(milliseconds: index * 50),
                    duration: 250.ms,
                  );
                }),

                const SizedBox(height: 24),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, _Filter filter) {
    final selected = _filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : context.textM,
          ),
        ),
        selected: selected,
        onSelected: (_) => setState(() => _filter = filter),
        selectedColor: AppColors.accent,
        backgroundColor: context.bgPanel,
        side: BorderSide(color: selected ? AppColors.accent : context.border),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _localFileCard(
    BuildContext context,
    ModelController ctrl,
    String filename,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 18, color: context.textM),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filename,
              style: TextStyle(fontSize: 13, color: context.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => ctrl.loadModel(filename),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Load',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.textM,
        letterSpacing: 0.3,
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    ModelController ctrl,
    AiModelInfo model,
  ) {
    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Model File', style: TextStyle(color: context.text)),
        content: Text(
          'Delete ${model.name}? (${model.sizeGb} GB will be freed)',
          style: TextStyle(color: context.textM),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              ctrl.deleteModel(model.filename);
              Get.back();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              elevation: 0,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveCustom(
    BuildContext context,
    ModelController ctrl,
    AiModelInfo model,
  ) {
    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove Custom Model',
          style: TextStyle(color: context.text),
        ),
        content: Text(
          'Remove "${model.name}" from your library?\nThis will also delete the downloaded file if any.',
          style: TextStyle(color: context.textM),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              ctrl.deleteCustomModel(model);
              Get.back();
              Get.snackbar(
                'Removed',
                '${model.name} removed from library.',
                snackPosition: SnackPosition.BOTTOM,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              elevation: 0,
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// Pill button for the import action
class _ImportButton extends StatelessWidget {
  final ModelController ctrl;
  const _ImportButton({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _showImportOptions(context),
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Import',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.textD,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Import Model',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.text,
                ),
              ),
              const SizedBox(height: 16),
              _importTile(
                context,
                icon: Icons.file_open_rounded,
                color: AppColors.accentHi,
                title: 'Import .gguf File',
                subtitle: 'Select a single model file',
                onTap: () {
                  Navigator.pop(context);
                  ctrl.importModelFromFile();
                },
              ),
              _importTile(
                context,
                icon: Icons.folder_open_rounded,
                color: AppColors.green,
                title: 'Import from Folder',
                subtitle: 'Scan folder for .gguf files',
                onTap: () {
                  Navigator.pop(context);
                  ctrl.importFromDirectory();
                },
              ),
              _importTile(
                context,
                icon: Icons.link_rounded,
                color: AppColors.orange,
                title: 'Add from URL',
                subtitle: 'Download a .gguf model from a URL',
                onTap: () {
                  Navigator.pop(context);
                  _showAddUrlDialog(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(color: context.text, fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: context.textD, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  void _showAddUrlDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    Get.dialog(
      AlertDialog(
        backgroundColor: context.bgPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Model from URL',
          style: TextStyle(color: context.text),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Model Name',
                labelStyle: TextStyle(color: context.textD, fontSize: 13),
                hintText: 'e.g. Mistral 7B Uncensored',
                hintStyle: TextStyle(color: context.textD.withValues(alpha: 0.5)),
                filled: true,
                fillColor: context.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: context.text, fontSize: 14),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Download URL',
                labelStyle: TextStyle(color: context.textD, fontSize: 13),
                hintText: 'https://huggingface.co/.../model.gguf',
                hintStyle: TextStyle(color: context.textD.withValues(alpha: 0.5)),
                filled: true,
                fillColor: context.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Cancel', style: TextStyle(color: context.textD)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty || url.isEmpty) {
                Get.snackbar(
                  'Missing Info',
                  'Please enter both name and URL.',
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }
              if (!url.startsWith('http')) {
                Get.snackbar(
                  'Invalid URL',
                  'URL must start with http:// or https://',
                  snackPosition: SnackPosition.BOTTOM,
                );
                return;
              }
              Get.back();
              ctrl.addCustomUrlModel(name: name, url: url);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Add Model',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
