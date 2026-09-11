import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Live upload/processing state.
///
/// Upload is a real measured percentage (dio reports bytes sent), so it
/// shows an exact ring plus how many MB have actually gone up.
/// Processing has no measurable percentage — the work happens on the
/// server — so rather than fake one, it runs an indeterminate sweep and
/// names the stages instead.
class UploadProgressCard extends StatefulWidget {
  final bool uploading;
  final double progress;
  final int totalBytes;

  const UploadProgressCard({
    super.key,
    required this.uploading,
    required this.progress,
    required this.totalBytes,
  });

  @override
  State<UploadProgressCard> createState() => UploadProgressCardState();
}

class UploadProgressCardState extends State<UploadProgressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _mb(num bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final percent = (widget.progress * 100).clamp(0, 100);
    final done = widget.progress >= 0.999;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glowCard(
        glowColor: AppColors.primary,
        glowOpacity: 0.18,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            height: 62,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: widget.uploading
                          // Smoothly animates between reported values so the
                          // ring glides rather than jumping in chunks.
                          ? TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: widget.progress),
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                              builder: (_, value, __) => CircularProgressIndicator(
                                value: value,
                                strokeWidth: 5,
                                backgroundColor: AppColors.surfaceBorder,
                                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            )
                          : CircularProgressIndicator(
                              strokeWidth: 5,
                              backgroundColor: AppColors.surfaceBorder,
                              valueColor: AlwaysStoppedAnimation(
                                Color.lerp(
                                  AppColors.secondary,
                                  AppColors.primary,
                                  // Ping-pongs 0->1->0 so the colour breathes
                                  // instead of snapping at the loop point.
                                  1 - (_pulse.value * 2 - 1).abs(),
                                )!,
                              ),
                            ),
                    ),
                    if (widget.uploading)
                      Text(
                        '${percent.round()}%',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else
                      Transform.scale(
                        // Gentle breathing sparkle while the server works.
                        scale: 0.9 + 0.15 * (1 - (_pulse.value * 2 - 1).abs()),
                        child: const Icon(Icons.auto_awesome,
                            size: 22, color: AppColors.secondary),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.uploading
                      ? (done ? 'Finishing upload...' : 'Uploading your video')
                      : 'Making your shorts',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                if (widget.uploading && widget.totalBytes > 0)
                  Text(
                    '${_mb(widget.totalBytes * widget.progress)} of ${_mb(widget.totalBytes)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  )
                else if (widget.uploading)
                  const Text(
                    'Starting upload...',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  )
                else
                  const Text(
                    'Transcribing, finding your best moments, then rendering '
                    'each clip. This takes a few minutes.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                if (widget.uploading) ...[
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: widget.progress),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      builder: (_, value, __) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceBorder,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
