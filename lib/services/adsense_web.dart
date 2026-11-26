// Google AdSense for the web app only (this file is imported only when dart:html exists).
//
// * The AdSense script is added to the page once, the first time an ad is about to show (never while ads are off).
// * Each placement ('discover', 'profile', ...) gets ONE ad element, created and requested ONCE per page load: when
//   the screen is rebuilt or the viewer navigates back, Flutter reuses the same element, so the ad isn't requested
//   again (no duplicate initialization).
// * If the script is blocked (ad blocker) or Google has no ad to show, the slot reports 'blocked' / 'unfilled' and
//   the app hides it, so viewers never see an empty box.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
library;

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

bool get adsenseSupported => true;

Completer<bool>? _script;
final Map<String, html.Element> _slots = {};
final Set<String> _registered = {};

Future<bool> loadAdsense(String client) {
  final existing = _script;
  if (existing != null) return existing.future;
  final done = Completer<bool>();
  _script = done;
  // A tiny helper so Dart can ask AdSense to fill an ad: (adsbygoogle = window.adsbygoogle || []).push({}).
  final helper = html.ScriptElement()
    ..text = 'window.viyoAdPush = function(){ (window.adsbygoogle = window.adsbygoogle || []).push({}); };';
  html.document.head?.append(helper);
  final s = html.ScriptElement()
    ..async = true
    ..src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$client'
    ..crossOrigin = 'anonymous';
  s.onLoad.first.then((_) {
    if (!done.isCompleted) done.complete(true);
  });
  s.onError.first.then((_) {
    if (!done.isCompleted) done.complete(false);          // blocked by an ad blocker or the network
  });
  html.document.head?.append(s);
  Timer(const Duration(seconds: 12), () {
    if (!done.isCompleted) done.complete(false);
  });
  return done.future;
}

String? registerAdSlot({required String placement, required String client, required String slot}) {
  final viewType = 'viyo-adsense-$placement';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final cached = _slots[placement];
      if (cached != null) return cached;                   // same element: no second ad request
      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('data-ad-client', client)
        ..setAttribute('data-ad-slot', slot)
        ..setAttribute('data-ad-format', 'auto')
        ..setAttribute('data-full-width-responsive', 'true');
      final box = html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.overflow = 'hidden'
        ..append(ins);
      _slots[placement] = box;
      // Ask AdSense to fill it once (only when the element is really in the page: AdSense looks for it there).
      var tries = 0;
      Timer.periodic(const Duration(milliseconds: 200), (t) {
        tries++;
        if (ins.isConnected == true) {
          t.cancel();
          try {
            globalContext.callMethod('viyoAdPush'.toJS);
          } catch (_) {}
        } else if (tries > 50) {
          t.cancel();                                       // never shown (screen left): no request
        }
      });
      return box;
    });
  }
  return viewType;
}

String adSlotStatus(String placement) {
  final box = _slots[placement];
  if (box == null) return 'pending';
  final ins = box.querySelector('ins.adsbygoogle');
  final status = ins?.getAttribute('data-ad-status');
  if (status == 'filled') return 'filled';
  if (status == 'unfilled') return 'unfilled';
  return 'pending';
}
