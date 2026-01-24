import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../data/models/media_images.dart';
import '../../core/utils/image_proxy.dart';

enum ImageSelectorType { poster, backdrop }

class ImageSelectorSheet extends StatefulWidget {
  final List<MediaImageInfo> images;
  final ImageSelectorType type;
  final String? currentUrl;
  final String? serverBaseUrl;
  final void Function(String url) onSelect;

  const ImageSelectorSheet({
    super.key,
    required this.images,
    required this.type,
    this.currentUrl,
    required this.serverBaseUrl,
    required this.onSelect,
  });

  @override
  State<ImageSelectorSheet> createState() => _ImageSelectorSheetState();
}

class _ImageSelectorSheetState extends State<ImageSelectorSheet> {
  @override
  Widget build(BuildContext context) {
    final isPoster = widget.type == ImageSelectorType.poster;
    final title = isPoster ? '选择海报' : '选择背景图';
    final crossAxisCount = isPoster ? 3 : 2;
    final aspectRatio = isPoster ? 2 / 3 : 16 / 9;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE5E5E5)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: Colors.grey,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          if (widget.images.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                '暂无可用图片',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                shrinkWrap: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: widget.images.length,
                itemBuilder: (context, index) {
                  final image = widget.images[index];
                  final imageUrl = ImageProxy.proxyTMDBIfNeeded(
                    image.url,
                    widget.serverBaseUrl,
                  );
                  final isSelected = widget.currentUrl != null &&
                      widget.currentUrl!.contains(image.filePath);

                  return GestureDetector(
                    onTap: () {
                      widget.onSelect(image.url);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.blue : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CupertinoActivityIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[200],
                                child: const Icon(
                                  CupertinoIcons.photo,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.checkmark,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            if (image.language != null &&
                                image.language!.isNotEmpty)
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    image.language!.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

Future<void> showImageSelector({
  required BuildContext context,
  required List<MediaImageInfo> images,
  required ImageSelectorType type,
  String? currentUrl,
  String? serverBaseUrl,
  required void Function(String url) onSelect,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ImageSelectorSheet(
      images: images,
      type: type,
      currentUrl: currentUrl,
      serverBaseUrl: serverBaseUrl,
      onSelect: onSelect,
    ),
  );
}
