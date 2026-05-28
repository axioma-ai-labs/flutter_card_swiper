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
    required this.commitThreshold,
    this.isHorizontalSwipingEnabled = true,
    this.isVerticalSwipingEnabled = true,
    this.allowedSwipeDirection = const AllowedSwipeDirection.all(),
    this.onSwipeDirectionChanged,
    this.onFirstAxisDecided,
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

  /// The commit threshold in pixels (mirrors `CardSwiper.threshold`). Used to
  /// decide when vertical resistance should taper off: once `|left|` is past
  /// the commit threshold we're effectively in "horizontal wins" territory
  /// and the vertical axis becomes purely cosmetic (1:1 with the finger).
  final double commitThreshold;

  /// Fires the first time the gesture commits to a primary axis. `true` =
  /// vertical, `false` = horizontal. Resets to `null` between gestures (via
  /// [reset]); hosts that care about the slop-window state can mirror this.
  final ValueChanged<bool?>? onFirstAxisDecided;

  double left = 0;
  double top = 0;
  double total = 0;
  double angle = 0;
  double scale;
  Offset difference = Offset.zero;

  bool? _firstAxisIsVertical; // null = not yet decided (inside slop window)
  double _cumulativeDx = 0;
  double _cumulativeDy = 0;
  static const double _directionLockThreshold = 18.0; // kTouchSlop
  // Virtual height for vertical resistance. Lower = resistance grows faster.
  // Chosen so reaching a 100 px vertical offset takes ~200 px of finger
  // travel (friction ~0.52 at rest), matching the pre-existing pull-up feel.
  static const double _verticalResistanceViewport = 450.0;

  late Animation<double> _leftAnimation;
  late Animation<double> _topAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _angleAnimation;
  late Animation<Offset> _differenceAnimation;

  double get _maxAngleInRadian => maxAngle * (math.pi / 180);

  /// `true` once the gesture has committed to vertical, `false` once
  /// committed to horizontal, `null` while still inside the pre-lock slop
  /// window. Hosts use this to gate UI (e.g. an "ask bro" warm-up that
  /// should only show when vertical was the user's first move).
  bool? get firstAxisIsVertical => _firstAxisIsVertical;

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
    if (_firstAxisIsVertical != null) {
      _firstAxisIsVertical = null;
      onFirstAxisDecided?.call(null);
    }
    _cumulativeDx = 0;
    _cumulativeDy = 0;
  }

  void update(double dx, double dy, bool inverseAngle) {
    // Accumulate deltas during the slop window to decide the gesture's
    // primary axis. Once decided, the lock is sticky for the whole drag —
    // but movement itself stays free 2D regardless of the lock.
    _cumulativeDx += dx.abs();
    _cumulativeDy += dy.abs();

    // Decide once: vertical zone is ~20° on each side of vertical
    // (70° from horizontal), tan(70°) ≈ 2.75. Tutorial-style cards that
    // disallow vertical fall back to horizontal so a small upward wrist
    // arc on a horizontal swipe doesn't strand the gesture.
    if (_firstAxisIsVertical == null) {
      final cumulativeMagnitude = _cumulativeDx + _cumulativeDy;
      if (cumulativeMagnitude > _directionLockThreshold) {
        final verticalAllowed =
            allowedSwipeDirection.up || allowedSwipeDirection.down;
        final horizontalAllowed =
            allowedSwipeDirection.left || allowedSwipeDirection.right;
        final leansVertical = _cumulativeDy > _cumulativeDx * 2.75;
        if (leansVertical && verticalAllowed) {
          _firstAxisIsVertical = true;
        } else if (horizontalAllowed) {
          _firstAxisIsVertical = false;
        } else if (verticalAllowed) {
          _firstAxisIsVertical = true;
        } else {
          _firstAxisIsVertical = false;
        }
        onFirstAxisDecided?.call(_firstAxisIsVertical);
      }
    }

    // ── Horizontal axis ──
    // Always tracks the finger 1:1 (subject to allowed directions). Even in
    // first=vertical mode the user is free to drift sideways — that's how
    // horizontal can "steal" the gesture from ask-bro.
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

    // ── Vertical axis ──
    // `preventInitialDownwardSwipe` only blocks once the gesture has
    // committed to vertical; a horizontal-first card can still drift down.
    final blockDownward = preventInitialDownwardSwipe &&
        (_firstAxisIsVertical ?? true) &&
        top >= 0 &&
        dy > 0;

    if (!blockDownward) {
      // Resistance applies only while the user is still "playing the
      // vertical game" — i.e. they committed vertical AND horizontal hasn't
      // taken over. Once horizontal crosses its commit threshold the
      // vertical axis is purely cosmetic and follows the finger 1:1.
      final applyResistance =
          (_firstAxisIsVertical ?? false) && left.abs() < commitThreshold;

      if (allowedSwipeDirection.up && allowedSwipeDirection.down) {
        if (top > 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.bottom);
        } else if (top < 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.top);
        }
        top = applyResistance ? _applyVerticalResistance(top, dy) : top + dy;
      } else if (allowedSwipeDirection.up) {
        if (top <= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.top);
          top = applyResistance ? _applyVerticalResistance(top, dy) : top + dy;
        }
      } else if (allowedSwipeDirection.down) {
        if (top >= 0) {
          onSwipeDirectionChanged?.call(CardSwiperDirection.bottom);
          top = applyResistance ? _applyVerticalResistance(top, dy) : top + dy;
        }
      } else {
        // Vertical disallowed entirely (e.g. tutorial cards) — freeze top.
        // Without this branch the card would drift vertically with diagonal
        // drags even though no vertical commit is possible.
      }
    }

    total = left + top;
    updateAngle(inverseAngle);
    updateScale();
    updateDifference();
  }

  /// Apply iOS-like overscroll resistance to vertical movement
  double _applyVerticalResistance(double currentTop, double dy) {
    final overscrollPast = currentTop.abs();
    final overscrollFraction =
        (overscrollPast / _verticalResistanceViewport).clamp(0.0, 1.0);

    // Friction increases as you drag further (like BouncingScrollPhysics)
    final friction = math.max(0.05, 0.52 * math.pow(1 - overscrollFraction, 2));

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
