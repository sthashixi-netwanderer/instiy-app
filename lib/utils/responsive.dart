import 'package:flutter/material.dart';

class Responsive {
  static const double _baseWidth = 360.0;
  static const double _baseHeight = 690.0;

  static double _scaleFactor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return (width / _baseWidth).clamp(0.8, 1.4);
  }

  static double _heightScaleFactor(BuildContext context) {
    final mq = MediaQuery.of(context);
    final height = mq.size.height - mq.viewInsets.bottom;
    return (height / _baseHeight).clamp(0.8, 1.4);
  }

  static double w(BuildContext context, double size) {
    return size * _scaleFactor(context);
  }

  static double h(BuildContext context, double size) {
    return size * _heightScaleFactor(context);
  }

  static double sp(BuildContext context, double size) {
    return size * _scaleFactor(context);
  }

  static EdgeInsets padding(BuildContext context, {
    double horizontal = 0,
    double vertical = 0,
  }) {
    final sf = _scaleFactor(context);
    return EdgeInsets.symmetric(
      horizontal: horizontal * sf,
      vertical: vertical * sf,
    );
  }

  static EdgeInsets allPadding(BuildContext context, double value) {
    final sf = _scaleFactor(context);
    return EdgeInsets.all(value * sf);
  }

  static double radius(BuildContext context, double value) {
    return value * _scaleFactor(context);
  }

  static double iconSize(BuildContext context, double size) {
    return size * _scaleFactor(context);
  }
}

extension ResponsiveExt on BuildContext {
  double get _sf => Responsive._scaleFactor(this);

  double rw(double size) => size * _sf;
  double rh(double size) => Responsive.h(this, size);
  double rsp(double size) => size * _sf;
  double rr(double size) => size * _sf;
  double ri(double size) => size * _sf;

  EdgeInsets rPadding({
    double horizontal = 0,
    double vertical = 0,
  }) => EdgeInsets.symmetric(
    horizontal: horizontal * _sf,
    vertical: vertical * _sf,
  );

  EdgeInsets rAll(double value) => EdgeInsets.all(value * _sf);

  // Responsive device checks
  bool get isMobile => MediaQuery.of(this).size.width < 600;
  bool get isTablet => MediaQuery.of(this).size.width >= 600 && MediaQuery.of(this).size.width < 1024;
  bool get isDesktop => MediaQuery.of(this).size.width >= 1024;

  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
}

