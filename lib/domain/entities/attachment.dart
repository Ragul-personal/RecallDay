import 'dart:convert';

/// What a topic attachment points at, which decides how it opens.
enum AttachmentKind {
  /// A picture copied into app storage. Opens in a full-screen viewer.
  image,

  /// A video copied into app storage. Plays in-app.
  video,

  /// Any other document copied into app storage (PDF, docx, …). Handed to
  /// whichever app on the phone claims the type.
  file,

  /// A YouTube link. Plays in-app in an embedded player.
  youtube,

  /// Any other web link. Opens in the phone's browser.
  link,
}

/// One attachment on a topic.
///
/// Stored inside `TopicModel.attachments` as a JSON string rather than as its
/// own Hive type. A `List<String>` needs no adapter, so adding attachments
/// didn't require registering a new typeId or a risky migration of the
/// existing box — the field simply reads back empty for topics saved by
/// earlier versions.
class Attachment {
  final String id;
  final AttachmentKind kind;

  /// Absolute file path for [AttachmentKind.image], [AttachmentKind.video] and
  /// [AttachmentKind.file]; a URL for [AttachmentKind.youtube] and
  /// [AttachmentKind.link].
  final String target;

  /// What to show in the list.
  final String name;

  final DateTime addedAt;

  const Attachment({
    required this.id,
    required this.kind,
    required this.target,
    required this.name,
    required this.addedAt,
  });

  bool get isLocalFile =>
      kind == AttachmentKind.image ||
      kind == AttachmentKind.video ||
      kind == AttachmentKind.file;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'target': target,
        'name': name,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: j['id'] as String,
        kind: AttachmentKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => AttachmentKind.file,
        ),
        target: j['target'] as String,
        name: (j['name'] as String?) ?? 'Attachment',
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  String encode() => jsonEncode(toJson());

  /// Decodes one stored entry, or null if it's unreadable — a corrupt entry
  /// shouldn't take the whole topic down with it.
  static Attachment? decode(String raw) {
    try {
      return Attachment.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static List<Attachment> decodeAll(List<String> raw) =>
      raw.map(decode).whereType<Attachment>().toList();

  static List<String> encodeAll(List<Attachment> list) =>
      list.map((a) => a.encode()).toList();

  /// Classify a URL the user typed.
  static AttachmentKind kindForUrl(String url) =>
      youTubeId(url) != null ? AttachmentKind.youtube : AttachmentKind.link;

  static String extensionOf(String path) =>
      path.contains('.') ? path.split('.').last.toLowerCase() : '';

  /// Classify a file by extension.
  ///
  /// This decides the icon and label, so it follows what the file *is* — a
  /// HEIC is an image whether or not the app can draw it. Whether it opens
  /// in-app is a separate question; see [rendersInApp].
  static AttachmentKind kindForPath(String path) {
    final ext = extensionOf(path);
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'wbmp', 'heic',
        'heif', 'avif', 'tiff', 'tif', 'svg'};
    const videos = {'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', 'm4v', 'wmv',
        'flv', 'mpg', 'mpeg', 'ts'};
    if (images.contains(ext)) return AttachmentKind.image;
    if (videos.contains(ext)) return AttachmentKind.video;
    return AttachmentKind.file;
  }

  /// Formats Flutter's own `Image` widget can decode.
  ///
  /// Notably missing: HEIC/HEIF — the default camera format on a lot of phones
  /// — plus AVIF, TIFF and SVG. Trying to draw one shows an error where a
  /// photo should be, so those are handed to the phone's gallery instead,
  /// which decodes them natively.
  static const Set<String> _flutterImages = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'wbmp',
  };

  /// Containers ExoPlayer handles on Android. AVI, WMV and FLV are not among
  /// them, so those go to whichever video app the user has.
  static const Set<String> _androidVideos = {
    'mp4', 'm4v', 'mkv', 'webm', '3gp', 'mov', 'ts',
  };

  /// Whether the app's own viewer can actually display this file.
  ///
  /// When false the file still opens — just handed to the system, which has
  /// codecs Flutter doesn't ship. Checking up front beats showing the user a
  /// broken viewer and asking them to back out of it.
  bool get rendersInApp {
    final ext = extensionOf(target);
    return switch (kind) {
      AttachmentKind.image => _flutterImages.contains(ext),
      AttachmentKind.video => _androidVideos.contains(ext),
      AttachmentKind.youtube => true,
      _ => false,
    };
  }

  /// Extracts a YouTube video id from the URL forms people actually paste:
  /// `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/live/`. Returns null if
  /// this isn't a YouTube link.
  static String? youTubeId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority) return null;
    final host = uri.host.toLowerCase().replaceFirst('www.', '');

    if (host == 'youtu.be') {
      final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      return _validId(id);
    }
    if (host != 'youtube.com' && host != 'm.youtube.com') return null;

    final v = uri.queryParameters['v'];
    if (v != null) return _validId(v);

    final segs = uri.pathSegments;
    for (final prefix in const ['shorts', 'embed', 'live', 'v']) {
      final i = segs.indexOf(prefix);
      if (i != -1 && i + 1 < segs.length) return _validId(segs[i + 1]);
    }
    return null;
  }

  static String? _validId(String id) =>
      RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id) ? id : null;
}
