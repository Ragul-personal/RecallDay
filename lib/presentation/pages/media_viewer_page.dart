import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_tokens.dart';
import '../../domain/entities/attachment.dart';

/// Opens an attachment the right way for its kind.
///
///   image / video / youtube -> in-app viewer (pushed below)
///   file                    -> handed to whatever app claims the type
///   link                    -> the phone's browser
///
/// Returns an error string when the OS refused to open it, so the caller can
/// tell the user instead of the tap doing nothing.
Future<String?> openAttachment(BuildContext context, Attachment a) async {
  switch (a.kind) {
    case AttachmentKind.image:
      if (!await File(a.target).exists()) return 'That file is missing.';
      if (!context.mounted) return null;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _ImageViewer(attachment: a)),
      );
      return null;

    case AttachmentKind.video:
      if (!await File(a.target).exists()) return 'That file is missing.';
      if (!context.mounted) return null;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _VideoViewer(attachment: a)),
      );
      return null;

    case AttachmentKind.youtube:
      final id = Attachment.youTubeId(a.target);
      if (id == null) return 'That YouTube link looks malformed.';
      if (!context.mounted) return null;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _YouTubeViewer(videoId: id, title: a.name),
        ),
      );
      return null;

    case AttachmentKind.file:
      if (!await File(a.target).exists()) return 'That file is missing.';
      final r = await OpenFilex.open(a.target);
      if (r.type == ResultType.done) return null;
      return r.type == ResultType.noAppToOpen
          ? 'No app on this phone can open ${a.name}.'
          : 'Could not open the file (${r.message}).';

    case AttachmentKind.link:
      final uri = Uri.tryParse(a.target);
      if (uri == null) return 'That link looks malformed.';
      final ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok ? null : 'No browser could open that link.';
  }
}

/// Full-screen, pinch-to-zoom image.
class _ImageViewer extends StatelessWidget {
  final Attachment attachment;
  const _ImageViewer({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          attachment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.file(
            File(attachment.target),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Could not display this image.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-app video playback with a scrub bar.
class _VideoViewer extends StatefulWidget {
  final Attachment attachment;
  const _VideoViewer({required this.attachment});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.file(File(widget.attachment.target));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      c.play();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = 'This video could not be played.\n$e');
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.attachment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : !ready
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      ),
                      VideoProgressIndicator(c, allowScrubbing: true),
                      const SizedBox(height: AppSpacing.sm),
                      IconButton(
                        iconSize: 44,
                        color: Colors.white,
                        icon: Icon(
                          c.value.isPlaying
                              ? Icons.pause_circle_filled_rounded
                              : Icons.play_circle_fill_rounded,
                        ),
                        onPressed: () => setState(
                          () => c.value.isPlaying ? c.pause() : c.play(),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// YouTube, played inside the app via the standard embed player.
class _YouTubeViewer extends StatefulWidget {
  final String videoId;
  final String title;
  const _YouTubeViewer({required this.videoId, required this.title});

  @override
  State<_YouTubeViewer> createState() => _YouTubeViewerState();
}

class _YouTubeViewerState extends State<_YouTubeViewer> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      // The embed URL rather than the watch page: the watch page tries to
      // hand off to the YouTube app and often refuses to render in a webview.
      ..loadRequest(
        Uri.parse(
          'https://www.youtube.com/embed/${widget.videoId}'
          '?autoplay=1&playsinline=1&rel=0',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () => launchUrl(
              Uri.parse('https://www.youtube.com/watch?v=${widget.videoId}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
