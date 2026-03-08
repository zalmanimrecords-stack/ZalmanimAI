/// API campaign model (matches server CampaignOut).
class Campaign {
  const Campaign({
    required this.id,
    this.artistId,
    required this.name,
    required this.title,
    required this.bodyText,
    this.bodyHtml,
    this.mediaUrl,
    required this.status,
    this.scheduledAt,
    this.sentAt,
    required this.createdAt,
    required this.updatedAt,
    this.targets = const [],
  });

  final int id;
  final int? artistId;
  final String name;
  final String title;
  final String bodyText;
  final String? bodyHtml;
  final String? mediaUrl;
  final String status;
  final String? scheduledAt;
  final String? sentAt;
  final String createdAt;
  final String updatedAt;
  final List<CampaignTarget> targets;

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final targetsJson = json['targets'];
    List<CampaignTarget> targetsList = const [];
    if (targetsJson is List) {
      targetsList = targetsJson
          .map((e) => e is Map<String, dynamic> ? CampaignTarget.fromJson(e) : null)
          .whereType<CampaignTarget>()
          .toList();
    }
    return Campaign(
      id: json['id'] as int,
      artistId: json['artist_id'] as int?,
      name: (json['name'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      bodyText: (json['body_text'] as String?) ?? '',
      bodyHtml: json['body_html']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      status: (json['status'] as String?) ?? 'draft',
      scheduledAt: json['scheduled_at']?.toString(),
      sentAt: json['sent_at']?.toString(),
      createdAt: (json['created_at']?.toString()) ?? '',
      updatedAt: (json['updated_at']?.toString()) ?? '',
      targets: targetsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'artist_id': artistId,
        'name': name,
        'title': title,
        'body_text': bodyText,
        'body_html': bodyHtml,
        'media_url': mediaUrl,
        'status': status,
        'scheduled_at': scheduledAt,
        'sent_at': sentAt,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'targets': targets.map((t) => t.toJson()).toList(),
      };
}

class CampaignTarget {
  const CampaignTarget({
    required this.id,
    required this.campaignId,
    required this.channelType,
    required this.externalId,
    this.channelPayload = const {},
  });

  final int id;
  final int campaignId;
  final String channelType;
  final String externalId;
  final Map<String, dynamic> channelPayload;

  factory CampaignTarget.fromJson(Map<String, dynamic> json) {
    final payload = json['channel_payload'];
    return CampaignTarget(
      id: json['id'] as int,
      campaignId: json['campaign_id'] as int,
      channelType: (json['channel_type'] as String?) ?? '',
      externalId: (json['external_id'] as String?) ?? '',
      channelPayload: payload is Map<String, dynamic> ? payload : {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'campaign_id': campaignId,
        'channel_type': channelType,
        'external_id': externalId,
        'channel_payload': channelPayload,
      };
}
