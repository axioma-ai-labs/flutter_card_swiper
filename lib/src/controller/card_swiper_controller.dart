import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_card_swiper/src/controller/controller_event.dart';

/// A controller that can be used to trigger swipes on a CardSwiper widget.
class CardSwiperController {
  final _eventController = StreamController<ControllerEvent>.broadcast();

  /// Stream of events that can be used to swipe the card.
  Stream<ControllerEvent> get events => _eventController.stream;

  /// Swipe the card to a specific direction.
  void swipe(CardSwiperDirection direction) {
    _eventController.add(ControllerSwipeEvent(direction));
  }

  // Undo the last swipe
  void undo() {
    _eventController.add(const ControllerUndoEvent());
  }

  // Change the top card to a specific index.
  void moveTo(int index) {
    _eventController.add(ControllerMoveEvent(index));
  }

  /// Feeds a vertical pan delta into the top card's drag state, as if a
  /// pointer were dragging by [dy] pixels. Negative = upward. Pair every
  /// series of updates with [injectVerticalDragEnd] so the release path
  /// (spring-back or commit) runs.
  void injectVerticalDragUpdate(double dy) {
    _eventController.add(ControllerInjectVerticalDragUpdate(dy));
  }

  /// Ends an injected vertical drag. [velocity] is the release velocity in
  /// pixels/second (matching a real pan-end).
  void injectVerticalDragEnd(Offset velocity) {
    _eventController.add(ControllerInjectVerticalDragEnd(velocity));
  }

  Future<void> dispose() async {
    await _eventController.close();
  }
}
