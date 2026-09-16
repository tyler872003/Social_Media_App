enum MediaType { image, video }

class MediaItem {
  final String url;
  final MediaType type;
  final String? thumbnailUrl;
  final String? publicId;

  MediaItem({
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.publicId,
  });

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      url: map['url'] as String,
      type: (map['type'] == 'video') ? MediaType.video : MediaType.image,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      publicId: map['publicId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'url': url,
    'type': type == MediaType.video ? 'video' : 'image',
    'thumbnailUrl': thumbnailUrl,
    'publicId': publicId,
  };
}
