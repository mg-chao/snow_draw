import 'package:flutter/material.dart';
import 'property_descriptor.dart';

/// Callback for when a property value changes
typedef PropertyChangeCallback<T> = void Function(T value);

/// Base class for rendering property controls
///
/// Each property renderer knows how to:
/// - Display the current value
/// - Handle user interactions
/// - Notify when the value changes
abstract class PropertyRenderer<T> {
  const PropertyRenderer();

  /// Build the widget for this property
  Widget build(
    BuildContext context,
    PropertyDescriptor<T> descriptor,
    StylePropertyContext propertyContext,
    PropertyChangeCallback<T> onChanged,
  );
}

/// Renderer for color properties
class ColorPropertyRenderer extends PropertyRenderer<Color> {
  const ColorPropertyRenderer();

  @override
  Widget build(
    BuildContext context,
    PropertyDescriptor<Color> descriptor,
    StylePropertyContext propertyContext,
    PropertyChangeCallback<Color> onChanged,
  ) {
    final value = descriptor.extractValue(propertyContext);
    final displayColor = value.isMixed
        ? descriptor.getDefaultValue(propertyContext)
        : (value.value ?? descriptor.getDefaultValue(propertyContext));

    // TODO: Implement color picker UI
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: displayColor,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Renderer for numeric slider properties (strokeWidth, opacity, etc.)
class SliderPropertyRenderer extends PropertyRenderer<double> {
  const SliderPropertyRenderer({
    required this.min,
    required this.max,
    this.divisions,
    this.label,
  });

  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? label;

  @override
  Widget build(
    BuildContext context,
    PropertyDescriptor<double> descriptor,
    StylePropertyContext propertyContext,
    PropertyChangeCallback<double> onChanged,
  ) {
    final value = descriptor.extractValue(propertyContext);
    final displayValue = value.isMixed
        ? descriptor.getDefaultValue(propertyContext)
        : (value.value ?? descriptor.getDefaultValue(propertyContext));

    // TODO: Implement slider UI
    return Slider(
      value: displayValue.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      label: label?.call(displayValue),
      onChanged: onChanged,
    );
  }
}

/// Renderer for enum dropdown properties
class DropdownPropertyRenderer<T> extends PropertyRenderer<T> {
  const DropdownPropertyRenderer({
    required this.options,
    required this.labelBuilder,
  });

  final List<T> options;
  final String Function(T) labelBuilder;

  @override
  Widget build(
    BuildContext context,
    PropertyDescriptor<T> descriptor,
    StylePropertyContext propertyContext,
    PropertyChangeCallback<T> onChanged,
  ) {
    final value = descriptor.extractValue(propertyContext);
    final displayValue = value.isMixed
        ? descriptor.getDefaultValue(propertyContext)
        : (value.value ?? descriptor.getDefaultValue(propertyContext));

    // TODO: Implement dropdown UI
    return DropdownButton<T>(
      value: displayValue,
      items: options.map((option) {
        return DropdownMenuItem<T>(
          value: option,
          child: Text(labelBuilder(option)),
        );
      }).toList(),
      onChanged: (newValue) {
        if (newValue != null) {
          onChanged(newValue);
        }
      },
    );
  }
}

/// Renderer for button group properties (text align, etc.)
class ButtonGroupPropertyRenderer<T> extends PropertyRenderer<T> {
  const ButtonGroupPropertyRenderer({
    required this.options,
    required this.iconBuilder,
  });

  final List<T> options;
  final IconData Function(T) iconBuilder;

  @override
  Widget build(
    BuildContext context,
    PropertyDescriptor<T> descriptor,
    StylePropertyContext propertyContext,
    PropertyChangeCallback<T> onChanged,
  ) {
    final value = descriptor.extractValue(propertyContext);
    final displayValue = value.isMixed
        ? descriptor.getDefaultValue(propertyContext)
        : (value.value ?? descriptor.getDefaultValue(propertyContext));

    // TODO: Implement button group UI
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((option) {
        final isSelected = option == displayValue;
        return IconButton(
          icon: Icon(iconBuilder(option)),
          color: isSelected ? Theme.of(context).primaryColor : null,
          onPressed: () => onChanged(option),
        );
      }).toList(),
    );
  }
}
