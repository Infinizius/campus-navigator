import 'package:flutter/material.dart';

class DraggableBottomSheet extends StatefulWidget {
  const DraggableBottomSheet(
      {super.key, required this.name, required this.child});
  final String name;
  final Widget child;
  @override
  State<DraggableBottomSheet> createState() => _DraggableBottomSheetState();
}

class _DraggableBottomSheetState extends State<DraggableBottomSheet> {
  final _controller = DraggableScrollableController();
  double _collapsed = 0.15;
  void _toggle() {
    if (!_controller.isAttached) return;
    _controller.animateTo(
        _controller.size < _collapsed + 0.05 ? 0.55 : _collapsed,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        _collapsed = (64 / constraints.maxHeight).clamp(0.08, 0.3);
        return DraggableScrollableSheet(
          initialChildSize: _collapsed,
          minChildSize: _collapsed,
          maxChildSize: 0.9,
          snap: true,
          snapSizes: [_collapsed, 0.55, 0.9],
          controller: _controller,
          builder: (context, scrollController) => Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant)),
            clipBehavior: Clip.antiAlias,
            child: CustomScrollView(controller: scrollController, slivers: [
              SliverToBoxAdapter(
                  child: InkWell(
                onTap: _toggle,
                child: SizedBox(
                    height: 64,
                    child: Column(children: [
                      const Grabber(),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(children: [
                            Expanded(
                                child: Text(widget.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall)),
                            const Icon(Icons.unfold_more, size: 20)
                          ])),
                    ])),
              )),
              SliverToBoxAdapter(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      child: widget.child)),
            ]),
          ),
        );
      });
}

class Grabber extends StatelessWidget {
  const Grabber({super.key});
  @override
  Widget build(BuildContext context) => Center(
      child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              borderRadius: BorderRadius.circular(2))));
}
