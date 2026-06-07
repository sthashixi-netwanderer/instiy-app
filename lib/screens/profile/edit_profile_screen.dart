import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/auth_service.dart';
import '../../services/sms_service.dart';
import '../../services/storage_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/image_picker_sheet.dart';
import '../../utils/responsive.dart';
import '../../widgets/responsive_layout.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _initialPhoneNumber;
  String? _verifiedPhoneNumber;
  bool _isPhoneVerified = true;
  bool _isSendingOtp = false;
  File? _avatarFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    if (user != null) {
      _nameController.text = user.fullName;
      _bioController.text = user.bio ?? '';
      _phoneController.text = user.phoneNumber ?? '';
      _initialPhoneNumber = user.phoneNumber ?? '';
    } else {
      _initialPhoneNumber = '';
    }
    _verifiedPhoneNumber = _initialPhoneNumber;
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPhoneChanged() {
    final currentPhone = _phoneController.text.trim();
    final isChanged = currentPhone != (_initialPhoneNumber ?? '');

    setState(() {
      if (isChanged && currentPhone.isNotEmpty && currentPhone != _verifiedPhoneNumber) {
        _isPhoneVerified = false;
      } else {
        _isPhoneVerified = true;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePickerSheet.pickSingle(context);
    if (file == null || !mounted) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Photo',
          toolbarColor: AppTheme.charcoalInk,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          cropStyle: CropStyle.circle,
        ),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          cropStyle: CropStyle.circle,
        ),
      ],
    );

    if (cropped != null && mounted) {
      setState(() {
        _avatarFile = File(cropped.path);
      });
    }
  }

  Future<void> _removeAvatar() async {
    final auth = ref.read(authProvider);
final confirmed = await AppTheme.showGlassDialog<bool>(
  context: context,
  title: const Text('Remove Profile Photo'),
  description: const Text('Are you sure you want to remove your profile photo? This will delete the image permanently.'),
  actions: [
    ShadButton.ghost(
      onPressed: () => Navigator.of(context).pop(false),
      child: const Text('Cancel'),
    ),
    ShadButton.destructive(
      onPressed: () => Navigator.of(context).pop(true),
      child: const Text('Remove'),
    ),
  ],
);

    if (confirmed != true || !mounted) return;

    final currentUrl = auth.user?.avatarUrl;

    // Delete from R2 if exists
    if (currentUrl != null && currentUrl.isNotEmpty) {
      try {
        await StorageService.deleteImage(currentUrl);
      } catch (_) {}
    }

    // Update profile with null avatar
    await auth.updateProfile(avatarUrl: null);
    if (mounted) {
      setState(() {
        _avatarFile = null;
      });
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Profile photo removed')),
      );
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isSendingOtp = true);

    try {
      // Check if phone is already taken by another user
      final userId = SupabaseService.auth.currentUser?.id;
      final taken = await AuthService.isPhoneTaken(phone, excludeUserId: userId);
      if (taken) {
        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(
              title: Text('This phone number is already registered to another account'),
            ),
          );
        }
        return;
      }

      final otp = (100000 + Random().nextInt(900000)).toString();
      final otpSent = await SmsService.sendOtp(to: phone, otp: otp);

      if (!otpSent) {
        throw Exception('Failed to send verification code.');
      }

      if (mounted) {
        _showPhoneVerificationDialog(otp, phone);
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  void _showPhoneVerificationDialog(String correctOtp, String newPhoneNumber) {
    final otpController = TextEditingController();
    bool isVerifying = false;
    String? otpError;

AppTheme.showGlassDialog(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verify Phone Number',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoalInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit verification code to $newPhoneNumber. Please enter it below to confirm your phone number.',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.mutedSteel,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            ShadInputFormField(
              id: 'otp',
              controller: otpController,
              label: const Text('Verification Code'),
              placeholder: const Text('Enter 6-digit code'),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            if (otpError != null) ...[
              const SizedBox(height: 8),
              Text(
                otpError!,
                style: const TextStyle(color: AppTheme.destructive, fontSize: 13),
              ),
            ],
            if (isVerifying) ...[
              const SizedBox(height: 16),
              const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: isVerifying ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ShadButton(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          final inputOtp = otpController.text.trim();
                          if (inputOtp.length != 6) {
                            setDialogState(() {
                              otpError = 'Enter a valid 6-digit code';
                            });
                            return;
                          }

                          if (inputOtp != correctOtp) {
                            setDialogState(() {
                              otpError = 'Incorrect code. Please try again.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isVerifying = true;
                            otpError = null;
                          });

                          try {
                            setState(() {
                              _verifiedPhoneNumber = newPhoneNumber;
                              _isPhoneVerified = true;
                            });
                            Navigator.of(context).pop();
                            ShadToaster.of(context).show(
                              const ShadToast(title: Text('Phone number verified! You can now save your changes.')),
                            );
                          } catch (e) {
                            setDialogState(() {
                              otpError = e.toString();
                            });
                          } finally {
                            setDialogState(() {
                              isVerifying = false;
                            });
                          }
                        },
                  child: const Text('Verify'),
                ),
              ],
            ),
          ],
        );
      },
    );
  },
).then((_) {
  otpController.dispose();
});
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = ref.read(authProvider);
    final navigator = Navigator.of(context);

    final newPhone = _phoneController.text.trim();
    final isPasswordChanged = _newPasswordController.text.isNotEmpty;

    setState(() => _isSaving = true);

    try {
      if (isPasswordChanged) {
        final email = auth.user?.email;
        if (email != null) {
          try {
            await SupabaseService.auth.signInWithPassword(
              email: email,
              password: _oldPasswordController.text,
            );
          } catch (e) {
            throw Exception('Incorrect current password. Please try again.');
          }
        } else {
          throw Exception('User email not found. Cannot verify password.');
        }
      }

      String? avatarUrl = auth.user?.avatarUrl;
      if (_avatarFile != null) {
        avatarUrl = await StorageService.uploadImage(
          file: _avatarFile!,
          folder: 'avatars',
        );
      }

      Future<void> performProfileUpdate(String? phoneToSave) async {
        await auth.updateProfile(
          fullName: _nameController.text.trim(),
          avatarUrl: avatarUrl,
          bio: _bioController.text.trim().isNotEmpty
              ? _bioController.text.trim()
              : null,
          phoneNumber: phoneToSave != null && phoneToSave.isNotEmpty ? phoneToSave : null,
        );

        if (isPasswordChanged) {
          await SupabaseService.auth.updateUser(
            UserAttributes(password: _newPasswordController.text),
          );
        }

        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        if (phoneToSave != null) {
          _initialPhoneNumber = phoneToSave;
        }

        if (mounted) {
          ShadToaster.of(context).show(
            const ShadToast(title: Text('Profile updated!')),
          );
          navigator.pop();
        }
      }

      await performProfileUpdate(newPhone);
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(title: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final user = ref.watch(authProvider).user;

    return ResponsiveLayout(
      type: ResponsiveLayoutType.form,
      backgroundColor: AppTheme.canvasWhite,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
              Padding(
                padding: context.rAll(16),
                child: Row(
                  children: [
                    ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    SizedBox(width: context.rw(8)),
                    Text(
                      'Edit Profile',
                      style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    ShadButton(
                      onPressed: (_isSaving || !_isPhoneVerified) ? null : _handleSave,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: context.rAll(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onTap: _pickAvatar,
                        child: Center(
                          child: Stack(
                            children: [
                              Container(
                                width: context.rw(100),
                                height: context.rh(100),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.grey[200],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _avatarFile != null
                                    ? Image.file(
                                        _avatarFile!,
                                        fit: BoxFit.cover,
                                        width: context.rw(100),
                                        height: context.rh(100),
                                      )
                                    : (user?.avatarUrl?.isNotEmpty == true
                                        ? CachedNetworkImage(
                                            imageUrl: user!.avatarUrl!,
                                            fit: BoxFit.cover,
                                            width: context.rw(100),
                                            height: context.rh(100),
                                            memCacheWidth: 100,
                                            placeholder: (_, url) => Center(
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                            errorWidget: (_, url, error) => Icon(
                                              LucideIcons.user,
                                              size: context.ri(50),
                                              color: Colors.grey[400],
                                            ),
                                          )
                                        : Icon(
                                            LucideIcons.user,
                                            size: context.ri(50),
                                            color: Colors.grey[400],
                                          )),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: context.rAll(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    LucideIcons.camera,
                                    size: context.ri(18),
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: context.rh(8)),
                      // Remove photo button (only if user has an avatar)
                      if (_avatarFile != null || (user?.avatarUrl?.isNotEmpty == true))
                        Center(
                          child: ShadButton.destructive(
                            onPressed: _removeAvatar,
                            size: ShadButtonSize.sm,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.trash2, size: context.ri(14)),
                                SizedBox(width: context.rw(6)),
                                const Text('Remove Photo'),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: context.rh(24)),
                      ShadInputFormField(
                        id: 'name',
                        controller: _nameController,
                        label: const Text('Full Name'),
                        textInputAction: TextInputAction.next,
                        validator: (v) => v.isEmpty ? 'Required' : null,
                      ),
                      SizedBox(height: context.rh(16)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: ShadInputFormField(
                              id: 'phone',
                              controller: _phoneController,
                              label: const Text('Phone Number'),
                              placeholder: const Text('+1 (555) 000-0000'),
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          if (!_isPhoneVerified) ...[
                            SizedBox(width: context.rw(8)),
                            Padding(
                              padding: EdgeInsets.only(bottom: context.rh(2)),
                              child: ShadButton(
                                onPressed: _isSendingOtp ? null : _sendPhoneOtp,
                                child: _isSendingOtp
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Verify'),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: context.rh(16)),
                      ShadInputFormField(
                        id: 'bio',
                        controller: _bioController,
                        label: const Text('Bio'),
                        placeholder: const Text('Tell others about yourself...'),
                        maxLines: 4,
                      ),
                      SizedBox(height: context.rh(24)),
                      const ShadSeparator.horizontal(),
                      SizedBox(height: context.rh(16)),
                      Text(
                        'Change Password',
                        style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: context.rh(16)),
                      ShadInputFormField(
                        id: 'oldPassword',
                        controller: _oldPasswordController,
                        label: const Text('Current Password'),
                        obscureText: true,
                        placeholder: const Text('Enter your current password'),
                        validator: (v) {
                          if ((_newPasswordController.text.isNotEmpty ||
                                  _confirmPasswordController.text.isNotEmpty) &&
                              v.isEmpty) {
                            return 'Current password is required to change password';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.rh(16)),
                      ShadInputFormField(
                        id: 'newPassword',
                        controller: _newPasswordController,
                        label: const Text('New Password'),
                        obscureText: true,
                        placeholder: const Text('Enter new password'),
                        validator: (v) {
                          if ((_oldPasswordController.text.isNotEmpty ||
                                  _confirmPasswordController.text.isNotEmpty) &&
                              v.isEmpty) {
                            return 'New password is required';
                          }
                          if (v.isNotEmpty && v.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.rh(16)),
                      ShadInputFormField(
                        id: 'confirmPassword',
                        controller: _confirmPasswordController,
                        label: const Text('Confirm New Password'),
                        obscureText: true,
                        placeholder: const Text('Confirm your new password'),
                        validator: (v) {
                          if (_newPasswordController.text.isNotEmpty && v.isEmpty) {
                            return 'Please confirm your new password';
                          }
                          if (v != _newPasswordController.text) {
                            return 'New passwords do not match';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: context.rh(32)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
