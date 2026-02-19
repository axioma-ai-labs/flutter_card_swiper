import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

class CardAnimation {
  CardAnimation({
    required this.animationController,
    required this.maxAngle,
    required this.initialScale,
    required this.initialOffset,
    required this.defaultDuration,
    this.isHorizontalSwipingEnabled = true,
    this.isVerticalSwipingEnabled = true,
    this.allowedSwipeDirection = const AllowedSwipeDirection.all(),
    this.onSwipeDirectionChanged,
    this.preventInitialDownwardSwipe = false,
  }) : scale = initialScale;

  final double maxAngle;
  final double initialScale;
  final Offset initialOffset;
  final Duration defaultDuration;
  final AnimationController animationController;
  final bool isHorizontalSwipingEnabled;
  final bool isVerticalSwipingEnabled;
  final AllowedSwipeDirection allowedSwipeDirection;
  final ValueChanged<CardSwiperDirection>? onSwipeDirectionChanged;
  final bool preventInitialDownwardSwipe;

  double left = 0;
  double top = 0;
  double total = 0;
  double angle = 0;
  double scale;
  Offset difference = Offset.zero;

  bool? _isVerticalSwipe; // null = not determined yet
  double _cumulativeDx = 0;
  double _cumulativeDy = 0;
  static const double _directionLockThreshold = 18.0; // kTouchSlop
  static const double _verticalResistanceViewport =
      800.0; // virtual height for resistance calc (higher = softer)

  late Animation<double> _leftAnimation;
  late Animation<double> _topAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _angleAnimation;
  late Animation<Offset> _differenceAnimation;

  double get _maxAngleInRadian => maxAngle * (math.pi / 180);

  void sync() {
    left = _leftAnimation.value;
    top = _topAnimation.value;
    scale = _scaleAnimation.value;
    angle = _angleAnimation.value;
    difference = _differenceAnimation.value;
  }

  void reset() {
    animationController.duration = defaultDuration;
    animationController.reset();
    left = 0;
    top = 0;
    total = 0;
    angle = 0;
    scale = initialScale;
    difference = Offset.zero;
    _isVerticalSwipe = null;
    _cumulativeDx = 0;
    _cumulativeDy = 0;
  }

  void update(double dx, double dy, bool inverseAngle) {
    // Accumulate deltas to determine direction (like Flutter's gesture arena)
    _cumulativeDx += dx.abs();
    _cumulativeDy += dy.abs();

    // Determine direction once cumulative movement exceeds threshold
    // Vertical zone is 20° on each side of vertical (70° from horizontal)
    // tan(70°) ≈ 2.75
    if (_isVerticalSwipe == null) {
      final total = _cumulativeDx + _cumulativeDy;
      if (total > _directionLockThreshold) {
        _isVerticalSwipe = _cumulativeDy > _cumulativeDx * 2.75;
      }
    }

    // Only allow horizontal movement if not locked to vertical
    if (_isVerticalSwipe != true) {
      if (allowedSwipeDirection.right && allowedSwipeDirection.left) {
        if (left > 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.right);
        } else if (left < 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.left);
        }
        left += dx;
      } else if (allowedSwipeDirection.right) {
        if (left >= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.right);
          left += dx;
        }
      } else if (allowedSwipeDirection.left) {
        if (left <= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.left);
          left += dx;
        }
      }
    }

    // Prevent initial downward swipe only for vertical swipes (horizontal swipes have full freedom)
    final isVerticalOrUndetermined = _isVerticalSwipe ?? true;
    final blockDownward = preventInitialDownwardSwipe &&
        isVerticalOrUndetermined &&
        top >= 0 &&
        dy > 0;

    if (!blockDownward) {
      if (allowedSwipeDirection.up && allowedSwipeDirection.down) {
        if (top > 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.bottom);
        } else if (top < 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.top);
        }
        // Apply resistance only for vertical swipes, free movement for horizontal
        if (_isVerticalSwipe ?? false) {
          top = _applyVerticalResistance(top, dy);
        } else {
          top += dy;
        }
      } else if (allowedSwipeDirection.up) {
        if (top <= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.top);
          if (_isVerticalSwipe ?? false) {
            top = _applyVerticalResistance(top, dy);
          } else {
            top += dy;
          }
        }
      } else if (allowedSwipeDirection.down) {
        if (top >= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.bottom);
          if (_isVerticalSwipe ?? false) {
            top = _applyVerticalResistance(top, dy);
          } else {
            top += dy;
          }
        }
      }
    }

    total = left + top;
    updateAngle(inverseAngle);
    updateScale();
    updateDifference();
  }

  /// Apply iOS-like overscroll resistance to vertical movement
  double _applyVerticalResistance(double currentTop, double dy) {
    final double overscrollPast = currentTop.abs();
    final double overscrollFraction =
        (overscrollPast / _verticalResistanceViewport).clamp(0.0, 1.0);

    // Friction increases as you drag further (like BouncingScrollPhysics)
    final double friction =
        math.max(0.05, 0.52 * math.pow(1 - overscrollFraction, 2));

    return currentTop + dy * friction;
  }

  void updateAngle(bool inverse) {
    angle = clampDouble(
      _maxAngleInRadian * left / 1000,
      -_maxAngleInRadian,
      _maxAngleInRadian,
    );
    if (inverse) angle *= -1;
  }

  void updateScale() {
    scale = clampDouble(initialScale + (total.abs() / 5000), initialScale, 1.0);
  }

  void updateDifference() {
    final discrepancy = (total / 10).abs();

    var diffX = 0.0;
    var diffY = 0.0;

    if (initialOffset.dx > 0) {
      diffX = discrepancy;
    } else if (initialOffset.dx < 0) {
      diffX = -discrepancy;
    }

    if (initialOffset.dy < 0) {
      diffY = -discrepancy;
    } else if (initialOffset.dy > 0) {
      diffY = discrepancy;
    }

    difference = Offset(diffX, diffY);
  }

  void animate(BuildContext context, CardSwiperDirection direction) {
    if (direction == CardSwiperDirection.none) return;
    animateToAngle(context, direction.angle);
  }

  void animateToAngle(BuildContext context, double targetAngle) {
    final size = MediaQuery.of(context).size;

    // Convert the angle to radians
    final adjustedAngle = (targetAngle - 90) * (math.pi / 180);

    // Calculate the target position based on the angle
    final magnitude = size.width; // Use screen width as base magnitude
    final targetX = magnitude * math.cos(adjustedAngle);
    final targetY = magnitude * math.sin(adjustedAngle);

    _leftAnimation = Tween<double>(
      begin: left,
      end: targetX,
    ).animate(animationController);

    _topAnimation = Tween<double>(
      begin: top,
      end: targetY,
    ).animate(animationController);

    _scaleAnimation = Tween<double>(
      begin: scale,
      end: 1.0,
    ).animate(animationController);

    _angleAnimation = Tween<double>(
      begin: angle,
      end: angle,
    ).animate(animationController);

    _differenceAnimation = Tween<Offset>(
      begin: difference,
      end: initialOffset,
    ).animate(animationController);

    animationController.forward();
  }

  void animateBack(BuildContext context, Offset velocity) {
    // Reset controller if it was already completed (e.g., cancelled swipe)
    if (animationController.status == AnimationStatus.completed) {
      animationController.reset();
    }

    animationController.duration = const Duration(milliseconds: 800);

    final curvedAnimation = CurvedAnimation(
      parent: animationController,
      curve: Curves.elasticOut,
    );

    _leftAnimation = Tween<double>(
      begin: left,
      end: 0,
    ).animate(curvedAnimation);
    _topAnimation = Tween<double>(
      begin: top,
      end: 0,
    ).animate(curvedAnimation);
    _scaleAnimation = Tween<double>(
      begin: scale,
      end: initialScale,
    ).animate(curvedAnimation);
    _angleAnimation = Tween<double>(
      begin: angle,
      end: 0,
    ).animate(curvedAnimation);
    _differenceAnimation = Tween<Offset>(
      begin: difference,
      end: Offset.zero,
    ).animate(curvedAnimation);

    animationController.forward();
  }

  void animateUndo(BuildContext context, CardSwiperDirection direction) {
    if (direction == CardSwiperDirection.none) return;
    animateUndoFromAngle(context, direction.angle);
  }

  void animateUndoFromAngle(BuildContext context, double undoAngle) {
    final size = MediaQuery.of(context).size;

    final adjustedAngle = (undoAngle - 90) * (math.pi / 180);

    final magnitude = size.width;
    final startX = magnitude * math.cos(adjustedAngle);
    final startY = magnitude * math.sin(adjustedAngle);

    // Calculate starting rotation angle based on swipe direction
    final startRotationAngle = clampDouble(
      _maxAngleInRadian * startX / 1000,
      -_maxAngleInRadian,
      _maxAngleInRadian,
    );

    _leftAnimation = Tween<double>(
      begin: startX,
      end: 0,
    ).animate(animationController);

    _topAnimation = Tween<double>(
      begin: startY,
      end: 0,
    ).animate(animationController);

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: scale,
    ).animate(animationController);

    _angleAnimation = Tween<double>(
      begin: startRotationAngle,
      end: 0,
    ).animate(animationController);

    _differenceAnimation = Tween<Offset>(
      begin: initialOffset,
      end: difference,
    ).animate(animationController);

    animationController.forward();
  }
}
