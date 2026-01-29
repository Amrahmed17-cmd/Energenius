# Energenius App Common Widgets

This directory contains reusable UI components that ensure consistent styling across the entire Energenius app.

## Custom Text Fields

### `CustomTextField`

A standard text input field with consistent styling. Use this for most text input needs.

```dart
CustomTextField(
  labelText: "First Name",
  prefixIcon: Icons.person,
  controller: _firstNameController,
  isDarkTheme: isDarkTheme,
  // Optional parameters
  obscureText: false,        // For password fields
  isReadOnly: false,         // For fields that should be read-only
  onTap: () { },             // For custom tap handling
  keyboardType: TextInputType.text,
  focusNode: myFocusNode,
  autoFocus: false,
  textInputAction: TextInputAction.next,
  onFieldSubmitted: (value) { },
  onChanged: (value) { },
)
```

### `CustomTextFormField`

A form-enabled version of the text field that supports validation.

```dart
CustomTextFormField(
  labelText: "Email",
  prefixIcon: Icons.email,
  controller: _emailController,
  isDarkTheme: isDarkTheme,
  // Form-specific parameter
  validator: (value) {
    if (value == null || value.isEmpty) {
      return "This field is required";
    }
    return null;
  },
  // Plus all parameters from CustomTextField
)
```

## Dropdown Field

### `CustomDropdown<T>`

A dropdown field that maintains consistent styling with the text fields.

```dart
CustomDropdown<String>(
  labelText: "Country",
  prefixIcon: Icons.public,
  value: selectedCountry,
  items: countriesList,
  isDarkTheme: isDarkTheme,
  onChanged: (value) {
    setState(() {
      selectedCountry = value;
    });
  },
  // Optional parameter for custom item rendering
  itemLabelBuilder: (item) => item.toString(),
)
```

## Usage Guidelines

1. Always pass the current theme's `isDarkTheme` value to ensure proper theming
2. Keep field labels concise and descriptive
3. Use appropriate icons from Material Icons that match the field purpose
4. Set appropriate keyboard types for different input types
5. Always handle the onChanged callback for interactive components
6. For form fields, provide meaningful validation messages

## Extending the Widgets

If you need to add functionality to these widgets, consider:

1. Adding parameters to the existing widgets rather than creating new ones
2. Maintaining consistent styling with the rest of the app
3. Documenting any new parameters in this README 