import 'package:at_common_flutter/services/size_config.dart';
import 'package:at_location_flutter/common_components/text_tile.dart';
import 'package:at_location_flutter/utils/constants/text_styles.dart';
import 'package:flutter/material.dart';

class TextTileRepeater extends StatelessWidget {
  final String? title;
  final ValueChanged<String>? onChanged;
  final List<String>? options;

  const TextTileRepeater({Key? key, this.title, this.options, this.onChanged})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250.toHeight,
      padding: EdgeInsets.fromLTRB(10.toWidth, 10.toHeight, 20.toWidth, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          title != null
              ? Text(title!, style: CustomTextStyles().grey16)
              : const SizedBox(),
          Expanded(
            child: ListView.separated(
              separatorBuilder: (context, index) {
                return const Divider();
              },
              itemCount: options!.length,
              itemBuilder: (context, index) {
                return SizedBox(
                  height: 50.toHeight,
                  child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        onChanged!(options![index]);
                        Navigator.pop(context);
                      },
                      child: TextTile(title: options![index])),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
