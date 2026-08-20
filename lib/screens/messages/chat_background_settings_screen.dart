import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:ui';

import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/image_picker_sheet.dart';
import '../../utils/responsive.dart';

class ChatBackgroundSettingsScreen extends ConsumerStatefulWidget {
  final String? conversationId;

  const ChatBackgroundSettingsScreen({super.key, this.conversationId});

  @override
  ConsumerState<ChatBackgroundSettingsScreen> createState() =>
      _ChatBackgroundSettingsScreenState();
}

class _ChatBackgroundSettingsScreenState
    extends ConsumerState<ChatBackgroundSettingsScreen> {
  String _bgType = 'none'; // 'none', 'gradient', 'image'
  String? _selectedGradient;
  dynamic _localImageFile;
  String? _existingImagePath;
  double _blurIntensity = 0.0;
  bool _isSaving = false;

  // Pre-defined gradients
  final Map<String, List<Color>> _gradients = {
    'Sunset': [const Color(0xFFFF5F6D), const Color(0xFFFFC371)],
    'Ocean': [const Color(0xFF2193b0), const Color(0xFF6dd5ed)],
    'Lavender': [const Color(0xFFe96443), const Color(0xFF904e95)],
    'Purple Magic': [const Color(0xFF4e54c8), const Color(0xFF8f94fb)],
    'Charcoal': [const Color(0xFF373B44), const Color(0xFF4286f4)],
    'Emerald': [const Color(0xFF11998e), const Color(0xFF38ef7d)],
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final bgProv = ref.read(chatBackgroundProvider);
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    if (bgProv.background == null) {
      await bgProv.loadBackground(userId, widget.conversationId);
    }

    if (bgProv.background != null && mounted) {
      final bg = bgProv.background!;
      setState(() {
        _bgType = bg.backgroundType;
        _selectedGradient = bg.gradientName;
        _existingImagePath = bg.localImagePath;
        _blurIntensity = bg.blurIntensity;
      });
    }
  }

  Future<void> _pickAndCropImage() async {
    final picked = await ImagePickerSheet.pickSingle(context);
    if (picked == null || !mounted) return;

    // On web, skip cropping — use the picked image as-is.
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _bgType = 'image';
          _localImageFile = picked;
        });
      }
      return;
    }

    // Mobile: crop the image.
    if (picked.path == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path!,
      aspectRatio: const CropAspectRatio(ratioX: 9, ratioY: 16),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Chat Background',
          toolbarColor: AppTheme.charcoalInk,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: true,
          cropStyle: CropStyle.rectangle,
        ),
        IOSUiSettings(
          title: 'Crop Chat Background',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.rectangle,
        ),
      ],
    );

    if (cropped != null && mounted) {
      final bytes = await cropped.readAsBytes();
      setState(() {
        _bgType = 'image';
        _localImageFile = bytes;
      });
    }
  }

  Future<void> _saveSettings() async {
    final auth = ref.read(authProvider);
    final userId = auth.user?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      // _localImageFile can be either a File (from image picker on mobile)
      // or Uint8List bytes (from cropper or web picker). The service expects
      // a file path, so write bytes to a temp file when needed.
      String? sourceImagePath;
      if (_bgType == 'image' && _localImageFile != null) {
        if (_localImageFile is File) {
          sourceImagePath = _localImageFile.path;
        } else if (_localImageFile is List<int>) {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File(
            '${tempDir.path}/chat_bg_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
          await tempFile.writeAsBytes(_localImageFile);
          sourceImagePath = tempFile.path;
        }
      }

      await ref.read(chatBackgroundProvider).setBackground(
            userId: userId,
            conversationId: widget.conversationId,
            backgroundType: _bgType,
            gradientName: _bgType == 'gradient' ? _selectedGradient : null,
            sourceImagePath: sourceImagePath,
            blurIntensity: _blurIntensity,
          );

      if (mounted) {
        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Chat background updated!'),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            backgroundColor: AppTheme.destructive,
            title: Text('Failed to save chat background: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Customize Background'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ShadButton(
              onPressed: _isSaving ? null : _saveSettings,
              size: ShadButtonSize.sm,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLarge = constraints.maxWidth > 700;
          return isLarge ? _buildWideLayout() : _buildNarrowLayout();
        },
      ),
    );
  }

  Widget _buildNarrowLayout() {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, topPad + 16, 16, 16),
      children: [
        _buildPreviewCard(),
        const SizedBox(height: 24),
        _buildSelectionControls(),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildPreviewCard(),
          ),
        ),
        VerticalDivider(width: 1, color: AppTheme.whisperBorder),
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _buildSelectionControls(),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live Preview',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 8),
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.whisperBorder),
            color: AppTheme.warmMist,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 1. Background Layer
              Positioned.fill(
                child: _buildBackgroundWidget(),
              ),
              // 2. Blur Filter Layer
              if (_blurIntensity > 0)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: _blurIntensity,
                      sigmaY: _blurIntensity,
                    ),
                    child: _buildBackgroundWidget(),
                  ),
                ),
              // 3. Simulated Chats overlay
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.1), // Translucent readability tint
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildMockBubble(
                        text: "Hey! Check out this new feature! \u{1F389}",
                        isMe: false,
                      ),
                      _buildMockBubble(
                        text: "Wow! I can customize my backgrounds and add blur too! Looks amazing! \u{1F60D}",
                        isMe: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBackgroundWidget() {
    if (_bgType == 'gradient' && _selectedGradient != null) {
      final colors = _gradients[_selectedGradient!];
      if (colors != null) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        );
      }
    } else if (_bgType == 'image') {
      if (_localImageFile != null) {
        // _localImageFile is Uint8List bytes on web, or a File on mobile.
        if (_localImageFile is List<int>) {
          return Image.memory(
            _localImageFile as dynamic,
            fit: BoxFit.cover,
          );
        }
        return Image.file(
          _localImageFile,
          fit: BoxFit.cover,
        );
      } else if (_existingImagePath != null) {
        return Image.file(
          File(_existingImagePath!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(color: AppTheme.canvasWhite),
        );
      }
    }

    // Default 'none'
    return Container(
      color: AppTheme.canvasWhite,
    );
  }

  Widget _buildMockBubble({required String text, required bool isMe}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.accent : AppTheme.pureSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 3),
            bottomRight: Radius.circular(isMe ? 3 : 12),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 1),
            )
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? Colors.white : AppTheme.charcoalInk,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Background Type',
          style: TextStyle(
            fontSize: context.rsp(14),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildTypeTab(type: 'none', label: 'None'),
            const SizedBox(width: 8),
            _buildTypeTab(type: 'gradient', label: 'Gradient'),
            const SizedBox(width: 8),
            _buildTypeTab(type: 'image', label: 'Custom Image'),
          ],
        ),
        const SizedBox(height: 24),
        if (_bgType == 'gradient') _buildGradientSelection(),
        if (_bgType == 'image') _buildImageSelection(),
        const SizedBox(height: 24),
        _buildBlurSettings(),
      ],
    );
  }

  Widget _buildTypeTab({required String type, required String label}) {
    final isSelected = _bgType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _bgType = type;
            if (type == 'gradient' && _selectedGradient == null) {
              _selectedGradient = _gradients.keys.first;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent : AppTheme.pureSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppTheme.accent : AppTheme.whisperBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppTheme.mutedSteel,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Gradient',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.2,
          ),
          itemCount: _gradients.length,
          itemBuilder: (context, index) {
            final key = _gradients.keys.elementAt(index);
            final colors = _gradients[key]!;
            final isSelected = _selectedGradient == key;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedGradient = key;
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.charcoalInk : Colors.transparent,
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      key,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildImageSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload Image',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                onPressed: _pickAndCropImage,
                leading: const Icon(LucideIcons.imagePlus, size: 16),
                child: Text(_localImageFile != null || _existingImagePath != null
                    ? 'Change Custom Image'
                    : 'Choose from Gallery'),
              ),
            ),
          ],
        ),
        if (_localImageFile != null || _existingImagePath != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Image will be automatically cropped to a 9:16 aspect ratio to fit the chat layout perfectly.',
            style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
          ),
        ],
      ],
    );
  }

  Widget _buildBlurSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blur Background',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
                ),
                SizedBox(height: 2),
                Text(
                  'Soften the background for higher text contrast',
                  style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
                ),
              ],
            ),
            Switch(
              value: _blurIntensity > 0,
              onChanged: (val) {
                setState(() {
                  _blurIntensity = val ? 5.0 : 0.0;
                });
              },
              activeThumbColor: AppTheme.accent,
            ),
          ],
        ),
        if (_blurIntensity > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Intensity', style: TextStyle(fontSize: 12, color: AppTheme.charcoalInk)),
              Expanded(
                child: Slider(
                  value: _blurIntensity,
                  min: 1.0,
                  max: 20.0,
                  activeColor: AppTheme.accent,
                  inactiveColor: AppTheme.warmMist,
                  onChanged: (val) {
                    setState(() {
                      _blurIntensity = val;
                    });
                  },
                ),
              ),
              Text(
                _blurIntensity.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.charcoalInk),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
