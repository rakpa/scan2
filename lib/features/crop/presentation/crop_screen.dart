import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scan2/features/camera/domain/quad_detector.dart';
import 'package:scan2/features/crop/domain/image_processor.dart';
import 'package:scan2/features/crop/presentation/widgets/draggable_quad.dart';

class CropScreen extends ConsumerStatefulWidget {
  final int? pageId;

  const CropScreen({super.key, this.pageId});

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  Quad _quad = const Quad.centered();
  ScanFilter _filter = ScanFilter.magic;
  double _brightness = 0;
  double _contrast = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(kIsWeb ? 'Crop & Enhance (Demo)' : 'Crop & Enhance'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Page saved')),
              );
              context.pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Container(
                  color: Colors.black87,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.description,
                              size: 96,
                              color: Colors.black38,
                            ),
                          ),
                        ),
                      ),
                      DraggableQuad(
                        initialQuad: _quad,
                        size: size,
                        onChanged: (q) => setState(() => _quad = q),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: ScanFilter.values.map((f) {
                          final selected = f == _filter;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(ImageProcessor.labelFor(f)),
                              selected: selected,
                              onSelected: (_) => setState(() => _filter = f),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Brightness', style: Theme.of(context).textTheme.labelMedium),
                    Slider(
                      value: _brightness,
                      min: -1,
                      max: 1,
                      onChanged: (v) => setState(() => _brightness = v),
                    ),
                    Text('Contrast', style: Theme.of(context).textTheme.labelMedium),
                    Slider(
                      value: _contrast,
                      min: -1,
                      max: 1,
                      activeColor: scheme.primary,
                      onChanged: (v) => setState(() => _contrast = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
