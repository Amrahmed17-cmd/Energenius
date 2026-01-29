import 'package:flutter/material.dart';

class CustomDropdown<T> extends StatelessWidget {
  final String labelText;
  final IconData prefixIcon;
  final T value;
  final List<T> items;
  final void Function(T?) onChanged;
  final bool isDarkTheme;
  final String Function(T)? itemLabelBuilder;

  const CustomDropdown({
    super.key,
    required this.labelText,
    required this.prefixIcon,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDarkTheme,
    this.itemLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonFormField<T>(
        dropdownColor: isDarkTheme ? Colors.black.withAlpha(204) : Colors.white,
        value: value,
        icon: Icon(Icons.arrow_drop_down, color: isDarkTheme ? Colors.white : Colors.blue),
        style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        decoration: InputDecoration(
          prefixIcon: Icon(prefixIcon, color: isDarkTheme ? Colors.white : Colors.blue),
          labelText: labelText,
          labelStyle: TextStyle(color: isDarkTheme ? Colors.white : Colors.grey[700]),
          filled: true,
          fillColor: isDarkTheme ? Colors.white.withAlpha(26) : Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: isDarkTheme ? Colors.white : Colors.blue, width: 1),
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          floatingLabelAlignment: FloatingLabelAlignment.start,
          alignLabelWithHint: false,
          floatingLabelStyle: TextStyle(
            color: isDarkTheme ? Colors.white : Colors.blue,
            backgroundColor: Colors.transparent,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          isCollapsed: false,
          isDense: false,
        ),
        items: items.map((T item) {
          final String label = itemLabelBuilder != null 
              ? itemLabelBuilder!(item) 
              : item.toString();
          
          return DropdownMenuItem<T>(
            value: item,
            child: Text(
              label, 
              style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
} 