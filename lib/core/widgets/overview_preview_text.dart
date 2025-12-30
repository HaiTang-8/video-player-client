import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OverviewPreviewText extends StatefulWidget {
  final String title;
  final String overview;
  final int maxLines;
  final TextStyle style;
  final TextStyle? linkStyle;
  final String linkText;

  const OverviewPreviewText({
    super.key,
    required this.title,
    required this.overview,
    required this.maxLines,
    required this.style,
    this.linkStyle,
    this.linkText = '全部>',
  });

  @override
  State<OverviewPreviewText> createState() => _OverviewPreviewTextState();
}

class _OverviewPreviewTextState extends State<OverviewPreviewText> {
  void _openFullOverview() {
    context.push(
      '/overview',
      extra: {'title': widget.title, 'overview': widget.overview},
    );
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSpan = TextSpan(text: widget.overview, style: widget.style);
        final basePainter = TextPainter(
          text: baseSpan,
          maxLines: widget.maxLines,
          textDirection: textDirection,
          textScaler: textScaler,
          locale: locale,
        )..layout(maxWidth: constraints.maxWidth);

        if (!basePainter.didExceedMaxLines) {
          return Text(widget.overview, style: widget.style);
        }

        final linkStyle =
            widget.linkStyle ?? widget.style.copyWith(color: Colors.blue);
        final lineHeight = basePainter.preferredLineHeight;
        final totalHeight = lineHeight * widget.maxLines;

        return SizedBox(
          height: totalHeight,
          child: Stack(
            children: [
              // 文本内容
              Positioned.fill(
                child: Text(
                  widget.overview,
                  style: widget.style,
                  maxLines: widget.maxLines,
                  overflow: TextOverflow.clip,
                ),
              ),
              // 右下角渐变遮罩 + "... 全部>"
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _openFullOverview,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white,
                          Colors.white,
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                    ),
                    padding: const EdgeInsets.only(left: 20),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '... ', style: widget.style),
                          TextSpan(text: widget.linkText, style: linkStyle),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
