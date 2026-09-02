/// Represents a downloadable/loadable AI model from the catalog.
class AiModelInfo {
  final String id;
  final String name;
  final String filename;
  final String url;
  final double sizeGb;
  final int minRamGb;
  final String label;        // UNCENSORED / STANDARD / CUSTOM
  final String badge;        // RECOMMENDED, HERETIC, etc.
  final String systemPrompt;
  final bool recommended;

  /// Lowercase hex SHA-256 of the GGUF, when the catalog publishes one.
  /// Empty means the download cannot be integrity-checked.
  final String sha256;

  const AiModelInfo({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeGb,
    required this.minRamGb,
    required this.label,
    required this.badge,
    required this.systemPrompt,
    this.recommended = false,
    this.sha256 = '',
  });

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      filename: json['filename'] as String,
      url: json['url'] as String,
      sizeGb: (json['sizeGb'] as num).toDouble(),
      minRamGb: (json['minRamGb'] as num).toInt(),
      label: json['label'] as String? ?? 'STANDARD',
      badge: json['badge'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      recommended: json['recommended'] as bool? ?? false,
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filename': filename,
        'url': url,
        'sizeGb': sizeGb,
        'minRamGb': minRamGb,
        'label': label,
        'badge': badge,
        'systemPrompt': systemPrompt,
        'recommended': recommended,
        'sha256': sha256,
      };

  bool get hasChecksum => sha256.isNotEmpty;

  bool get isUncensored => label == 'UNCENSORED';
  bool get isStandard => label == 'STANDARD';
  bool get isCustom => label == 'CUSTOM';
}
