import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import '../models/institution_model.dart';
import '../services/institution_service.dart';
import '../config/app_theme.dart';
import '../utils/responsive.dart';

class MultiInstitutionPicker extends StatefulWidget {
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String hint;

  const MultiInstitutionPicker({
    super.key,
    required this.selectedValues,
    required this.onChanged,
    required this.label,
    required this.hint,
  });

  @override
  State<MultiInstitutionPicker> createState() => _MultiInstitutionPickerState();
}

class _MultiInstitutionPickerState extends State<MultiInstitutionPicker> {
  void _openSearchSheet() {
    showShadSheet(
      context: context,
      builder: (context) {
        return ShadSheet(
          title: const Text('Select Campuses / Universities'),
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: _MultiInstitutionSearchContent(
              selectedValues: widget.selectedValues,
              onChanged: widget.onChanged,
              hint: widget.hint,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _openSearchSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.selectedValues.isEmpty
                        ? widget.hint
                        : widget.selectedValues.join(', '),
                    style: TextStyle(
                      color: widget.selectedValues.isEmpty
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF1E293B),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                const Icon(LucideIcons.chevronDown, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
        if (widget.selectedValues.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.selectedValues.map((val) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(val, style: const TextStyle(fontSize: 12, color: AppTheme.accent)),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        final updated = List<String>.from(widget.selectedValues)..remove(val);
                        widget.onChanged(updated);
                      },
                      child: const Icon(LucideIcons.x, size: 14, color: AppTheme.accent),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

class _MultiInstitutionSearchContent extends StatefulWidget {
  final List<String> selectedValues;
  final ValueChanged<List<String>> onChanged;
  final String hint;

  const _MultiInstitutionSearchContent({
    required this.selectedValues,
    required this.onChanged,
    required this.hint,
  });

  @override
  State<_MultiInstitutionSearchContent> createState() =>
      _MultiInstitutionSearchContentState();
}

class _MultiInstitutionSearchContentState
    extends State<_MultiInstitutionSearchContent> {
  final _searchController = TextEditingController();
  List<Institution> _allInstitutions = [];
  List<Institution> _filteredInstitutions = [];
  Set<String> _selected = {};
  bool _isLoading = true;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedValues);
    _loadInstitutions();
  }

  Future<void> _loadInstitutions() async {
    try {
      final list = await InstitutionService.getInstitutions();
      setState(() {
        _allInstitutions = list;
        _filteredInstitutions = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'Failed to load institutions: $e';
        _isLoading = false;
      });
    }
  }

  void _filterList(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredInstitutions = _allInstitutions;
      } else {
        _filteredInstitutions = _allInstitutions
            .where((inst) =>
                inst.name.toLowerCase().contains(query.toLowerCase()) ||
                inst.code.toLowerCase().contains(query.toLowerCase()) ||
                (inst.location ?? '')
                    .toLowerCase()
                    .contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _toggleInstitution(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return SizedBox(
      height: mediaQuery.size.height * 0.65,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: context.rh(12)),
            child: ShadInput(
              controller: _searchController,
              placeholder: const Text('Search by university name or acronym...'),
              leading: Icon(LucideIcons.search, size: context.ri(18)),
              onChanged: _filterList,
            ),
          ),
          if (_selected.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(bottom: context.rh(8)),
              child: Text(
                '${_selected.length} selected',
                style: TextStyle(fontSize: context.rsp(13), color: AppTheme.mutedSteel),
              ),
            ),
          ],
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: context.rAll(24),
                          child: Text(_errorMsg,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      )
                    : _filteredInstitutions.isEmpty
                        ? Center(
                            child: Text('No universities found',
                                style: TextStyle(color: const Color(0xFF64748B), fontSize: context.rsp(14))))
                        : ListView.builder(
                            itemExtent: context.rh(72),
                            padding: EdgeInsets.symmetric(horizontal: context.rw(8)),
                            itemCount: _filteredInstitutions.length,
                            itemBuilder: (context, index) {
                              final inst = _filteredInstitutions[index];
                              final isSelected = _selected.contains(inst.name);
                              return Material(
                                type: MaterialType.transparency,
                                child: CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (_) => _toggleInstitution(inst.name),
                                  secondary: inst.logoUrl != null &&
                                          inst.logoUrl!.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(context.rr(4)),
                                          child: CachedNetworkImage(
                                            imageUrl: inst.logoUrl!,
                                            width: context.rw(36),
                                            height: context.rh(36),
                                            fit: BoxFit.cover,
                                            memCacheWidth: 36,
                                            placeholder: (_, _) => Container(
                                                color: AppTheme.warmMist),
                                            errorWidget: (_, _, _) => Container(
                                              color: AppTheme.warmMist,
                                              child: Icon(
                                                  LucideIcons.graduationCap,
                                                  size: context.ri(20)),
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: context.rw(36),
                                          height: context.rh(36),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(context.rr(4)),
                                            border: Border.all(
                                                color: const Color(0xFFE2E8F0)),
                                          ),
                                          child: Center(
                                            child: Text(
                                              inst.code.substring(
                                                  0,
                                                  math.min(
                                                      3, inst.code.length)),
                                              style: TextStyle(
                                                  fontSize: context.rsp(11),
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFF475569)),
                                            ),
                                          ),
                                        ),
                                  title: Text(inst.name,
                                      style: TextStyle(
                                        fontSize: context.rsp(14),
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? AppTheme.accent
                                            : const Color(0xFF1E293B),
                                      )),
                                  subtitle: inst.location != null
                                      ? Text('${inst.code} \u2022 ${inst.location}',
                                          style: TextStyle(fontSize: context.rsp(12)))
                                      : Text(inst.code, style: TextStyle(fontSize: context.rsp(12))),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  activeColor: AppTheme.accent,
                                ),
                              );
                            },
                          ),
          ),
          SizedBox(height: context.rh(12)),
          Row(
            children: [
              if (_selected.isNotEmpty)
                ShadButton.outline(
                  onPressed: () {
                    setState(() => _selected.clear());
                  },
                  child: const Text('Clear'),
                ),
              const Spacer(),
              ShadButton(
                onPressed: () {
                  widget.onChanged(_selected.toList());
                  Navigator.of(context).pop();
                },
                child: Text('Done (${_selected.length})'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
