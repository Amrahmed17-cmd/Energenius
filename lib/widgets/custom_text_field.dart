import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String labelText;
  final IconData prefixIcon;
  final TextEditingController controller;
  final bool obscureText;
  final bool isDarkTheme;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final FocusNode? focusNode;
  final bool autoFocus;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;
  final void Function(String)? onChanged;
  final Widget? suffixIcon;

  const CustomTextField({
    super.key,
    required this.labelText,
    required this.prefixIcon,
    required this.controller,
    this.obscureText = false,
    required this.isDarkTheme,
    this.isReadOnly = false,
    this.onTap,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.focusNode,
    this.autoFocus = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          prefixIcon: Icon(prefixIcon, color: isDarkTheme ? Colors.white : Colors.blue),
          suffixIcon: suffixIcon,
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
        readOnly: isReadOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        focusNode: focusNode,
        autofocus: autoFocus,
        textInputAction: textInputAction,
        onSubmitted: onFieldSubmitted,
        onChanged: onChanged,
      ),
    );
  }
}

// For form validation, also provide a FormField version
class CustomTextFormField extends StatelessWidget {
  final String labelText;
  final IconData prefixIcon;
  final TextEditingController controller;
  final bool obscureText;
  final bool isDarkTheme;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final FocusNode? focusNode;
  final bool autoFocus;
  final TextInputAction? textInputAction;
  final void Function(String?)? onFieldSubmitted;
  final void Function(String?)? onChanged;
  final Widget? suffixIcon;

  const CustomTextFormField({
    super.key,
    required this.labelText,
    required this.prefixIcon,
    required this.controller,
    this.obscureText = false,
    required this.isDarkTheme,
    this.isReadOnly = false,
    this.onTap,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.focusNode,
    this.autoFocus = false,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        style: TextStyle(color: isDarkTheme ? Colors.white : Colors.black),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          prefixIcon: Icon(prefixIcon, color: isDarkTheme ? Colors.white : Colors.blue),
          suffixIcon: suffixIcon,
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
        readOnly: isReadOnly,
        onTap: onTap,
        validator: validator,
        keyboardType: keyboardType,
        focusNode: focusNode,
        autofocus: autoFocus,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
      ),
    );
  }
}
