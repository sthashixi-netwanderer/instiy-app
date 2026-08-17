import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/institution_model.dart';
import '../services/institution_service.dart';
import '../config/app_theme.dart';
import 'institution_list_tile.dart';

class SearchableInstitutionPicker extends StatefulWidget {
  final String? selectedValue;
  final ValueChanged<String?> onSelected;
  final String label;
  final String hint;

  const SearchableInstitutionPicker({
    super.key,
    required this.selectedValue,
    required this.onSelected,
    required this.label,
    required this.hint,
  });

  @override
  State<SearchableInstitutionPicker> createState() => _SearchableInstitutionPickerState();
}

class _SearchableInstitutionPickerState extends State<SearchableInstitutionPicker> {
  void _openSearchSheet() {
    showShadSheet(
      context: context,
      builder: (context) {
        return ShadSheet(
          title: const Text('Select Campus / University'),
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: _InstitutionSearchContent(
              selectedValue: widget.selectedValue,
              onSelected: widget.onSelected,
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
                    widget.selectedValue == null || widget.selectedValue!.isEmpty
                        ? widget.hint
                        : widget.selectedValue!,
                    style: TextStyle(
                      color: widget.selectedValue == null || widget.selectedValue!.isEmpty
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF1E293B),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(LucideIcons.chevronDown, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InstitutionSearchContent extends StatefulWidget {
  final String? selectedValue;
  final ValueChanged<String?> onSelected;
  final String hint;

  const _InstitutionSearchContent({
    required this.selectedValue,
    required this.onSelected,
    required this.hint,
  });

  @override
  State<_InstitutionSearchContent> createState() => _InstitutionSearchContentState();
}

class _InstitutionSearchContentState extends State<_InstitutionSearchContent> {
  final _searchController = TextEditingController();
  List<Institution> _allInstitutions = [];
  List<Institution> _filteredInstitutions = [];
  bool _isLoading = true;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
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
                (inst.location ?? '').toLowerCase().contains(query.toLowerCase()))
            .toList();
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
    return SizedBox(
      height: 450,
      child: Material(
        color: Colors.transparent,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ShadInput(
              controller: _searchController,
              placeholder: const Text('Search by university name or acronym...'),
              leading: const Icon(LucideIcons.search, size: 18),
              onChanged: _filterList,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMsg.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _errorMsg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : _filteredInstitutions.isEmpty
                        ? const Center(
                            child: Text(
                              'No universities found',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          )
                        : Material(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _filteredInstitutions.length,
                              itemBuilder: (context, index) {
                                final inst = _filteredInstitutions[index];
                                final isSelected = widget.selectedValue == inst.name;
                                return InstitutionListTileRadio(
                                  institution: inst,
                                  isSelected: isSelected,
                                  onTap: () {
                                    widget.onSelected(inst.name);
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    ),
  );
  }
}
