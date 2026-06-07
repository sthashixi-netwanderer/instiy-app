import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../config/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../services/wallet_service.dart';
import '../../services/auth_service.dart';
import '../../services/business_profile_service.dart';
import '../../widgets/scanner_overlay.dart';
import '../../utils/responsive.dart';

class WalletTagScreen extends StatefulWidget {
  const WalletTagScreen({super.key});

  @override
  State<WalletTagScreen> createState() => _WalletTagScreenState();
}

class _WalletTagScreenState extends State<WalletTagScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  
  bool _isProcessing = false;
  String? _displayName;
  String? _avatarUrl;
  bool _isLoadingName = true;

  Rect? _detectedRect;
  Timer? _clearDetectedRectTimer;
  Size? _lastPreviewSize;
  Size? _lastWidgetSize;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDisplayName();
  }

  Future<void> _loadDisplayName() async {
    try {
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoadingName = false;
        });
        return;
      }

      // Get user's profile to have avatarUrl and fullName
      final user = await AuthService.getCurrentUserProfile();

      // Check if seller and has business name
      final profile = await BusinessProfileService.getProfile(userId);
      if (profile != null && profile.businessName != null && profile.businessName!.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _displayName = profile.businessName;
            _avatarUrl = user?.avatarUrl;
            _isLoadingName = false;
          });
          return;
        }
      }

      // Otherwise, get user's full name
      if (mounted) {
        setState(() {
          _displayName = user?.fullName;
          _avatarUrl = user?.avatarUrl;
          _isLoadingName = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingName = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _clearDetectedRectTimer?.cancel();
    super.dispose();
  }

  Rect _mapRectToScreen(Rect rect, Size previewSize, Size widgetSize) {
    final scaleX = widgetSize.width / previewSize.width;
    final scaleY = widgetSize.height / previewSize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final offsetX = (widgetSize.width - previewSize.width * scale) / 2;
    final offsetY = (widgetSize.height - previewSize.height * scale) / 2;

    final mappedRect = Rect.fromLTRB(
      rect.left * scale + offsetX,
      rect.top * scale + offsetY,
      rect.right * scale + offsetX,
      rect.bottom * scale + offsetY,
    );

    return mappedRect.inflate(16);
  }

  Rect? _getBoundingBox(List<Offset>? points) {
    if (points == null || points.isEmpty) return null;
    double left = points[0].dx;
    double top = points[0].dy;
    double right = points[0].dx;
    double bottom = points[0].dy;

    for (final point in points) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final boundingBox = _getBoundingBox(barcode.corners);
    final String code = barcode.rawValue ?? '';
    
    _lastPreviewSize = capture.size;

    if (boundingBox != null && _lastPreviewSize != null && _lastWidgetSize != null) {
      final screenRect = _mapRectToScreen(boundingBox, _lastPreviewSize!, _lastWidgetSize!);
      setState(() {
        _detectedRect = screenRect;
      });

      _clearDetectedRectTimer?.cancel();
      _clearDetectedRectTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _detectedRect = null;
          });
        }
      });
    }

    // We expect the QR code to be in format: "instiy:pay:<user_id>"
    if (code.startsWith('instiy:pay:')) {
      setState(() {
        _isProcessing = true;
      });

      // Brief delay to show target frame snapping
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _scannerController.stop();

      final recipientId = code.replaceFirst('instiy:pay:', '');
      
      if (!mounted) return;

      // Look up recipient info
      String recipientName = 'User';
      try {
        final recipientUser = await SupabaseService.client
            .from('users')
            .select('full_name')
            .eq('id', recipientId)
            .maybeSingle();

        final recipientBiz = await SupabaseService.client
            .from('business_profiles')
            .select('business_name')
            .eq('seller_id', recipientId)
            .maybeSingle();

        recipientName = recipientBiz?['business_name'] as String? ?? 
                        recipientUser?['full_name'] as String? ?? 
                        'User';
      } catch (_) {
        // Fall back to generic 'User'
      }

      if (!mounted) return;
      
      // Stop scanner temporarily to show amount dialog
      final success = await _showSendMoneyDialog(recipientId, recipientName);
      
      if (mounted) {
        if (success == true) {
          Navigator.of(context).pop(); // Close scanner
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('Transfer Successful'),
              description: Text('Funds have been sent to the user.'),
            ),
          );
        } else {
          setState(() {
            _isProcessing = false;
            _detectedRect = null;
          });
          _scannerController.start();
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isProcessing = true;
        });

        // Brief delay to show target frame snapping
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        
        ShadToaster.of(context).show(
          const ShadToast.destructive(
            title: Text('Invalid QR Code'),
            description: Text('This QR code does not belong to an Instiy user.'),
          ),
        );
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isProcessing = false;
              _detectedRect = null;
            });
          }
        });
      }
    }
  }

  Future<bool?> _showSendMoneyDialog(String recipientId, String recipientName) {
    final amountCtrl = TextEditingController();
    bool isSubmitting = false;

    return showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => ShadDialog(
          title: const Text('Send Money'),
          description: Text('Enter the amount you wish to transfer to $recipientName.'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: context.rh(16)),
              ShadInput(
                controller: amountCtrl,
                placeholder: const Text('Amount (GH₵)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                leading: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('GH₵', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(height: context.rh(24)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.ghost(
                    onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  SizedBox(width: context.rw(8)),
                  ShadButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                            if (amount <= 0) {
                              ShadToaster.of(ctx).show(
                                const ShadToast.destructive(
                                  title: Text('Invalid Amount'),
                                  description: Text('Please enter a valid transfer amount.'),
                                ),
                              );
                              return;
                            }

                            setStateDialog(() => isSubmitting = true);

                            try {
                              // Verify balance first
                              final hasBalance = await WalletService.checkBalance(amount);
                              if (!hasBalance) {
                                if (ctx.mounted) {
                                  ShadToaster.of(ctx).show(
                                    const ShadToast.destructive(
                                      title: Text('Insufficient Balance'),
                                      description: Text('You do not have enough funds for this transfer.'),
                                    ),
                                  );
                                  setStateDialog(() => isSubmitting = false);
                                }
                                return;
                              }

                              await WalletService.transferToUser(
                                recipientId: recipientId,
                                amount: amount,
                                description: 'QR Tag Transfer',
                              );

                              if (ctx.mounted) {
                                Navigator.of(ctx).pop(true);
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ShadToaster.of(ctx).show(
                                  ShadToast.destructive(
                                    title: const Text('Transfer Failed'),
                                    description: Text(e.toString()),
                                  ),
                                );
                                setStateDialog(() => isSubmitting = false);
                              }
                            }
                          },
                    child: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Send Funds'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pureSurface,
      appBar: AppBar(
        title: const Text('Wallet Tag', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: AppTheme.pureSurface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.mutedSteel,
          indicatorColor: AppTheme.accent,
          tabs: const [
            Tab(icon: Icon(LucideIcons.qrCode), text: 'Receive'),
            Tab(icon: Icon(LucideIcons.scan), text: 'Send'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceiveTab(),
          _buildSendTab(),
        ],
      ),
    );
  }

  Widget _buildReceiveTab() {
    final userId = SupabaseService.auth.currentUser?.id ?? '';
    final qrData = 'instiy:pay:$userId';
    final cleanedTag = _displayName != null ? _displayName!.replaceAll(RegExp(r'\s+'), '') : '';

    return Container(
      color: AppTheme.canvasWhite,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // White QR card matching screenshot layout
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: context.rw(240),
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Colors.black,
                      ),
                      embeddedImage: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? CachedNetworkImageProvider(_avatarUrl!)
                          : const AssetImage('assets/logo_highres.png') as ImageProvider,
                      embeddedImageStyle: const QrEmbeddedImageStyle(
                        size: Size(48, 48),
                      ),
                    ),
                    // Beautiful centered logo container with spacing, border, and shadow
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _avatarUrl!,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => Image.asset('assets/logo_highres.png'),
                                errorWidget: (_, _, _) => Image.asset('assets/logo_highres.png'),
                              )
                            : Image.asset(
                                'assets/logo_highres.png',
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.rh(32)),
              // Name and Tag section below the QR code card
              if (_isLoadingName)
                const SizedBox(
                  height: 60,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                )
              else if (_displayName != null) ...[
                Text(
                  _displayName!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(26),
                    fontWeight: FontWeight.bold,
                    color: AppTheme.charcoalInk,
                  ),
                ),
                SizedBox(height: context.rh(8)),
                Text(
                  'Scan to pay \$$cleanedTag',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.rsp(15),
                    color: AppTheme.mutedSteel,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSendTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastWidgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
            ),
            // Overlay for scanner
            AnimatedScannerOverlay(
              cutOutSize: context.rw(250),
              borderRadius: 12,
              borderWidth: 4,
              detectedRect: _detectedRect,
            ),
            Positioned(
              top: context.rh(60),
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    'Scan to Send',
                    style: TextStyle(
                      fontSize: context.rsp(20),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: context.rh(8)),
                  Text(
                    'Align the QR code within the frame',
                    style: TextStyle(color: Colors.white70, fontSize: context.rsp(14)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
