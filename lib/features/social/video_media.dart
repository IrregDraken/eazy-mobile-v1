import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class EazyVideoMedia extends StatefulWidget {
  const EazyVideoMedia({super.key, required this.url, this.fit = BoxFit.cover, this.autoPlay = true, this.showControls = true});
  final String url;
  final BoxFit fit;
  final bool autoPlay;
  final bool showControls;

  @override
  State<EazyVideoMedia> createState() => _EazyVideoMediaState();
}

class _EazyVideoMediaState extends State<EazyVideoMedia> {
  late final VideoPlayerController controller;
  bool muted = true;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller.setLooping(true);
    controller.initialize().then((_) async {
      await controller.setVolume(0);
      if (widget.autoPlay) await controller.play();
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => error = 'Video could not be loaded');
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> togglePlayback() async {
    if (!controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await controller.setVolume(muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return const ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.broken_video_outlined, color: Colors.white70, size: 34)));
    if (!controller.value.isInitialized) return const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)));
    final size = controller.value.size;
    return GestureDetector(
      onTap: togglePlayback,
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(controller)),
          ),
        ),
        if (widget.showControls && !controller.value.isPlaying)
          const Center(child: CircleAvatar(backgroundColor: Colors.black45, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30))),
        if (widget.showControls)
          Positioned(
            right: 8,
            bottom: 8,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
              onPressed: toggleMute,
              icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 19),
            ),
          ),
      ]),
    );
  }
}
