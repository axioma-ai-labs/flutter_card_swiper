import 'package:flutter/widgets.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

sealed class ControllerEvent {
  const ControllerEvent();
}

class ControllerSwipeEvent extends ControllerEvent {
  final CardSwiperDirection direction;
  const ControllerSwipeEvent(this.direction);
}

class ControllerUndoEvent extends ControllerEvent {
  const ControllerUndoEvent();
}

class ControllerMoveEvent extends ControllerEvent {
  final int index;
  const ControllerMoveEvent(this.index);
}

/// Injects a synthetic vertical pan delta into the top card's drag state.
///
/// Used by hosts that want to forward overscroll from a nested scroll view
/// into the same physics the card uses for first-party pan input.
class ControllerInjectVerticalDragUpdate extends ControllerEvent {
  final double dy;
  const ControllerInjectVerticalDragUpdate(this.dy);
}

/// Ends an injected vertical drag, mirroring a real pan release. [velocity]
/// is in pixels/second (matching a real pan-end), used to decide between
/// spring-back and fling commit.
class ControllerInjectVerticalDragEnd extends ControllerEvent {
  final Offset velocity;
  const ControllerInjectVerticalDragEnd(this.velocity);
}
