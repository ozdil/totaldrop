// SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Full foldable and large-screen verification:
// - AdaptiveMetrics window classes, book/tabletop postures, flat crease & IME fallback
// - Mathematical hinge-avoidance across every screen in LTR (en) and RTL (ar)
// - Live cover <-> unfolded <-> book <-> tabletop continuity with zero state loss
// - Dialog hinge avoidance via DisplayFeatureSubScreen
// - Narrow cover (320x740), unfolded square (674x841), book, and tabletop at 200% scale

import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:totaldrop/data/background_access.dart';
import 'package:totaldrop/data/settings_repository.dart';
import 'package:totaldrop/l10n/app_localizations.dart';
import 'package:totaldrop/src/rust/api/l10n.dart' show ShownText;
import 'package:totaldrop/src/rust/api/transfer.dart';
import 'package:totaldrop/src/rust/frb_generated.dart';
import 'package:totaldrop/ui/core/adaptive.dart';
import 'package:totaldrop/ui/core/common.dart';
import 'package:totaldrop/ui/core/mark.dart';
import 'package:totaldrop/ui/core/theme.dart';
import 'package:totaldrop/ui/home/home_view.dart';
import 'package:totaldrop/ui/receive/receive_view.dart';
import 'package:totaldrop/ui/receive/receive_view_model.dart';
import 'package:totaldrop/ui/send/send_view.dart';
import 'package:totaldrop/ui/send/send_view_model.dart';
import 'package:totaldrop/ui/settings/settings_view.dart';
import 'package:totaldrop/ui/setup/background_setup_view.dart';

import 'fakes.dart';

class _MockRust implements RustLibApi {
  @override
  String crateApiL10NRevealControls({required String name}) => name;

  @override
  bool crateApiL10NNeedsEnglish({required String tag, required String key}) =>
      false;

  @override
  bool crateApiL10NHasDraftTranslation({required String tag}) => false;

  @override
  ShownText crateApiL10NShownText({required String text}) =>
      ShownText(text: text, short: true, hidden: true);

  @override
  String crateApiTransferDefaultServer() => 'wss://rendezvous.totaldrop.app';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends ChangeNotifier implements SettingsRepository {
  @override
  String get defaultServer => 'wss://rendezvous.totaldrop.app';
  @override
  String get server => defaultServer;
  @override
  bool get usesDefaultServer => true;
  @override
  bool get privacyMode => false;
  @override
  Future<void> setServer(String url) async {}
  @override
  Future<void> setPrivacyMode(bool on) async {}
  @override
  Future<void> resetServer() async {}
  @override
  bool get backgroundSetupSeen => true;
  @override
  bool get backgroundSkipped => false;
  @override
  bool get backgroundReminded => false;
  @override
  Future<void> setBackgroundSetupSeen({required bool skipped}) async {}
  @override
  Future<void> setBackgroundReminded() async {}
}

class _Limits implements BackgroundAccess {
  const _Limits();

  @override
  Future<BackgroundState> state() async =>
      const BackgroundState(exempt: false, maker: 'Xiaomi', autostart: true);

  @override
  Future<bool> open(BackgroundPage page) async => true;
}

const _coverScreen = Size(320, 740);
const _coverTall = Size(344, 882);
const _unfoldedSquare = Size(674, 841);
const _bookSize = Size(840, 700);
const _tabletopFlip = Size(412, 915);

const _bookHinge = Rect.fromLTWH(408, 0, 24, 700);
const _tabletopHinge = Rect.fromLTWH(0, 350, 840, 0);
const _flipTabletopHinge = Rect.fromLTWH(0, 456, 412, 0);

const _bookFeature = DisplayFeature(
  bounds: _bookHinge,
  type: DisplayFeatureType.hinge,
  state: DisplayFeatureState.postureHalfOpened,
);

const _flatCreaseFeature = DisplayFeature(
  bounds: Rect.fromLTWH(337, 0, 0, 841),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

const _tabletopFeature = DisplayFeature(
  bounds: _tabletopHinge,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

const _flipTabletopFeature = DisplayFeature(
  bounds: _flipTabletopHinge,
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

/// Configures the test FlutterView to match a real Android foldable display
/// window (so MediaQuery, Navigator/DialogRoute, and LayoutBuilder all see the
/// exact logical dimensions and Jetpack WindowManager display features).
void _setFoldableView(
  WidgetTester tester,
  Size size, {
  List<DisplayFeature> displayFeatures = const [],
}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.displayFeatures = displayFeatures;
}

Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) => MaterialApp(
  theme: buildTheme(fallbackScheme(Brightness.light)),
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: SystemMotion(child: child!),
  ),
  home: home,
);

/// Verifies that no primary interactive control or key content widget
/// intersects [hinge] (allowing a 0.5 dp floating-point rounding epsilon).
void _expectNoHingeOverlap(WidgetTester tester, Rect hinge) {
  final targets = <Finder>[
    find.byWidgetPredicate((w) => w is ButtonStyleButton),
    find.byType(TextField),
    find.byType(Switch),
    find.byType(TotalDropMark),
    find.byType(VerificationWords),
    find.byType(TransferProgress),
    find.byType(Card),
  ];

  // Expand zero-thickness fold lines slightly so widgets crossing the fold
  // axis are detected reliably.
  final checkRect = Rect.fromLTRB(
    hinge.width == 0 ? hinge.left - 1 : hinge.left + 0.5,
    hinge.height == 0 ? hinge.top - 1 : hinge.top + 0.5,
    hinge.width == 0 ? hinge.right + 1 : hinge.right - 0.5,
    hinge.height == 0 ? hinge.bottom + 1 : hinge.bottom - 0.5,
  );

  for (final finder in targets) {
    for (final element in finder.evaluate()) {
      final render = element.renderObject;
      if (render is! RenderBox || !render.hasSize) continue;
      final topLeft = render.localToGlobal(Offset.zero);
      final rect = topLeft & render.size;
      if (rect.isEmpty) continue;
      expect(
        rect.overlaps(checkRect),
        isFalse,
        reason:
            '${element.widget.runtimeType} at $rect overlaps hinge $checkRect',
      );
    }
  }
}

void main() {
  final settings = _Settings();

  setUpAll(() => RustLib.initMock(api: _MockRust()));

  group('AdaptiveMetrics', () {
    test('classifies compact, cover, medium, and expanded windows', () {
      final cover = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(size: _coverScreen),
      );
      expect(cover.sizeClass, WindowSizeClass.compact);
      expect(cover.isNarrowCover, isTrue);
      expect(cover.horizontalPadding, 16);
      expect(cover.useBookLayout, isFalse);

      final phone = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(size: Size(360, 740)),
      );
      expect(phone.sizeClass, WindowSizeClass.compact);
      expect(phone.isNarrowCover, isFalse);
      expect(phone.horizontalPadding, 24);

      final medium = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(
          size: _unfoldedSquare,
          displayFeatures: [_flatCreaseFeature],
        ),
      );
      expect(medium.sizeClass, WindowSizeClass.medium);
      expect(medium.posture, FoldPosture.flat);
      expect(medium.flatVerticalCreaseX, 337);
      expect(medium.useBookLayout, isTrue);

      final expanded = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(size: Size(1024, 768)),
      );
      expect(expanded.sizeClass, WindowSizeClass.expanded);
      expect(expanded.useBookLayout, isTrue);
    });

    test('detects book posture, tabletop posture, and IME fallback', () {
      final book = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(size: _bookSize, displayFeatures: [_bookFeature]),
      );
      expect(book.posture, FoldPosture.book);
      expect(book.hinge, _bookHinge);
      expect(book.useBookLayout, isTrue);
      expect(book.useTabletopLayout, isFalse);

      final tabletop = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(
          size: _bookSize,
          displayFeatures: [_tabletopFeature],
        ),
      );
      expect(tabletop.posture, FoldPosture.tabletop);
      expect(tabletop.hinge, _tabletopHinge);
      expect(tabletop.useTabletopLayout, isTrue);

      final tabletopWithKeyboard = AdaptiveMetrics.fromMediaQuery(
        const MediaQueryData(
          size: _bookSize,
          displayFeatures: [_tabletopFeature],
          viewInsets: EdgeInsets.only(bottom: 260),
        ),
      );
      expect(tabletopWithKeyboard.posture, FoldPosture.tabletop);
      expect(tabletopWithKeyboard.keyboardBlockingTabletop, isTrue);
      expect(tabletopWithKeyboard.useTabletopLayout, isFalse);
    });
  });

  group('Book posture hinge avoidance and RTL mirroring', () {
    testWidgets(
      'HomeView splits cleanly across vertical hinge in LTR and RTL',
      (tester) async {
        _setFoldableView(
          tester,
          _bookSize,
          displayFeatures: const [_bookFeature],
        );
        addTearDown(tester.view.reset);

        // LTR: brand mark in left pane, action cards in right pane.
        await tester.pumpWidget(
          _app(HomeView(onSend: () {}, onReceive: () {}, onSettings: () {})),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectNoHingeOverlap(tester, _bookHinge);

        final ltrMark = tester.getCenter(find.byType(TotalDropMark));
        final ltrCard = tester.getCenter(find.byType(Card).first);
        expect(ltrMark.dx, lessThan(_bookHinge.left));
        expect(ltrCard.dx, greaterThan(_bookHinge.right));

        // RTL (Arabic): brand mark in right pane, action cards in left pane.
        await tester.pumpWidget(
          _app(
            HomeView(onSend: () {}, onReceive: () {}, onSettings: () {}),
            locale: const Locale('ar'),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectNoHingeOverlap(tester, _bookHinge);

        final rtlMark = tester.getCenter(find.byType(TotalDropMark));
        final rtlCard = tester.getCenter(find.byType(Card).first);
        expect(rtlMark.dx, greaterThan(_bookHinge.right));
        expect(rtlCard.dx, lessThan(_bookHinge.left));
      },
    );

    testWidgets('Every screen avoids the vertical hinge in book posture', (
      tester,
    ) async {
      _setFoldableView(
        tester,
        _bookSize,
        displayFeatures: const [_bookFeature],
      );
      addTearDown(tester.view.reset);

      final sendRepo = FakeRepository();
      final sendWaitingVm = SendViewModel(
        repository: sendRepo,
        fileSource: FakeFileSource(),
      )..addFakeFileForTest('Annual Report 2026.pdf');

      final sendTransferRepo = FakeRepository();
      final sendTransferVm = SendViewModel(
        repository: sendTransferRepo,
        fileSource: FakeFileSource(),
      )..addFakeFileForTest('Annual Report 2026.pdf');

      final recvOfferRepo = FakeRepository();
      final recvOfferVm = ReceiveViewModel(repository: recvOfferRepo)
        ..setInput('7-harbor-rocket');

      final sendErrorRepo = FakeRepository();
      final sendErrorVm = SendViewModel(
        repository: sendErrorRepo,
        fileSource: FakeFileSource(),
      )..addFakeFileForTest('Annual Report 2026.pdf');

      final cases = <(String, Widget, Future<void> Function())>[
        (
          'send picking empty',
          SendView(
            viewModel: SendViewModel(
              repository: FakeRepository(),
              fileSource: FakeFileSource(),
            ),
          ),
          () async {},
        ),
        (
          'send picking files',
          SendView(
            viewModel: SendViewModel(
              repository: FakeRepository(),
              fileSource: FakeFileSource(),
            )..addFakeFileForTest('Annual Report 2026.pdf'),
          ),
          () async {},
        ),
        (
          'send text',
          SendView(
            viewModel:
                SendViewModel(
                    repository: FakeRepository(),
                    fileSource: FakeFileSource(),
                  )
                  ..setTextMode(true)
                  ..setText('Foldable clipboard note'),
          ),
          () async {},
        ),
        (
          'send waiting',
          SendView(viewModel: sendWaitingVm),
          () async {
            unawaited(sendWaitingVm.start());
            sendRepo.prepared.complete(FakeSession());
          },
        ),
        (
          'send transferring',
          SendView(viewModel: sendTransferVm),
          () async {
            unawaited(sendTransferVm.start());
            sendTransferRepo.prepared.complete(FakeSession());
            await tester.pump();
            sendTransferRepo.events.add(
              const TransferEvent(
                kind: EventKind.connected,
                words: ['abandon', 'ability', 'absorb', 'abstract'],
                done: 0,
                total: 0,
                summary: null,
                error: null,
              ),
            );
            sendTransferRepo.events.add(
              const TransferEvent(
                kind: EventKind.progress,
                words: [],
                done: 500,
                total: 1000,
                summary: null,
                error: null,
              ),
            );
          },
        ),
        (
          'send failed',
          SendView(viewModel: sendErrorVm),
          () async {
            unawaited(sendErrorVm.start());
            sendErrorRepo.prepared.complete(FakeSession());
            await tester.pump();
            sendErrorRepo.events.add(
              const TransferEvent(
                kind: EventKind.failed,
                words: [],
                done: 0,
                total: 0,
                summary: null,
                error: TransferError(
                  kind: ErrorKind.connect,
                  detail: 'timed out after 30 s',
                  cause: 'TimedOut',
                ),
              ),
            );
          },
        ),
        (
          'receive entering',
          ReceiveView(
            viewModel: ReceiveViewModel(repository: FakeRepository()),
          ),
          () async {},
        ),
        (
          'receive offered',
          ReceiveView(viewModel: recvOfferVm),
          () async {
            unawaited(recvOfferVm.connect());
            recvOfferRepo.connected.complete(FakeOffer());
          },
        ),
        (
          'settings',
          SettingsView(
            settings: settings,
            version: '0.4.0-beta.1',
            background: const _Limits(),
          ),
          () async {},
        ),
        (
          'background setup',
          BackgroundSetupView(
            access: const _Limits(),
            firstRun: true,
            onDone: ({required skipped}) {},
          ),
          () async {},
        ),
      ];

      for (final (name, widget, reach) in cases) {
        await tester.pumpWidget(_app(widget));
        await reach();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'overflow in $name');
        _expectNoHingeOverlap(tester, _bookHinge);
      }
    });

    testWidgets('Stop confirmation AlertDialog avoids the hinge in book mode', (
      tester,
    ) async {
      _setFoldableView(
        tester,
        _bookSize,
        displayFeatures: const [_bookFeature],
      );
      addTearDown(tester.view.reset);

      final repo = FakeRepository();
      final vm = SendViewModel(repository: repo, fileSource: FakeFileSource())
        ..addFakeFileForTest('clip.mp4');

      await tester.pumpWidget(_app(SendView(viewModel: vm)));
      unawaited(vm.start());
      repo.prepared.complete(FakeSession());
      await tester.pump();
      repo.events.add(
        const TransferEvent(
          kind: EventKind.progress,
          words: [],
          done: 10,
          total: 100,
          summary: null,
          error: null,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.maybePop());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dialogBox = tester.getRect(find.byType(AlertDialog));
      expect(dialogBox.overlaps(_bookHinge), isFalse);
    });
  });

  group('Tabletop / Flex posture', () {
    testWidgets(
      'SendView waiting places code in upper display pane and actions in lower control pane',
      (tester) async {
        _setFoldableView(
          tester,
          _bookSize,
          displayFeatures: const [_tabletopFeature],
        );
        addTearDown(tester.view.reset);

        final repo = FakeRepository();
        final vm = SendViewModel(repository: repo, fileSource: FakeFileSource())
          ..addFakeFileForTest('photo.jpg');

        await tester.pumpWidget(_app(SendView(viewModel: vm)));
        unawaited(vm.start());
        repo.prepared.complete(FakeSession());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        _expectNoHingeOverlap(tester, _tabletopHinge);

        final codeRect = tester.getRect(find.text('7-harbor-rocket'));
        final copyButtonRect = tester.getRect(
          find.byWidgetPredicate((w) => w is OutlinedButton),
        );
        expect(codeRect.bottom, lessThanOrEqualTo(_tabletopHinge.top + 0.5));
        expect(
          copyButtonRect.top,
          greaterThanOrEqualTo(_tabletopHinge.bottom - 0.5),
        );
      },
    );

    testWidgets('Clamshell tabletop renders Home and Receive offer cleanly', (
      tester,
    ) async {
      _setFoldableView(
        tester,
        _tabletopFlip,
        displayFeatures: const [_flipTabletopFeature],
      );
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(HomeView(onSend: () {}, onReceive: () {}, onSettings: () {})),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      _expectNoHingeOverlap(tester, _flipTabletopHinge);

      final repo = FakeRepository();
      final vm = ReceiveViewModel(repository: repo)
        ..setInput('7-harbor-rocket');
      await tester.pumpWidget(_app(ReceiveView(viewModel: vm)));
      unawaited(vm.connect());
      repo.connected.complete(FakeOffer());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      _expectNoHingeOverlap(tester, _flipTabletopHinge);
    });
  });

  group('Live fold/unfold continuity', () {
    testWidgets(
      'preserves text input across cover -> unfolded -> book -> tabletop transitions',
      (tester) async {
        addTearDown(tester.view.reset);

        final vm =
            SendViewModel(
                repository: FakeRepository(),
                fileSource: FakeFileSource(),
              )
              ..setTextMode(true)
              ..setText('continuity-payload-12345');

        final states = <(Size, List<DisplayFeature>)>[
          (_coverTall, const []),
          (_unfoldedSquare, const [_flatCreaseFeature]),
          (_bookSize, const [_bookFeature]),
          (_bookSize, const [_tabletopFeature]),
          (_coverTall, const []),
        ];

        for (final (size, features) in states) {
          _setFoldableView(tester, size, displayFeatures: features);
          await tester.pumpWidget(_app(SendView(viewModel: vm)));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(vm.text, 'continuity-payload-12345');
          expect(find.text('continuity-payload-12345'), findsOneWidget);
        }
      },
    );
  });

  group('Foldable form factors x locales x 200% font scale', () {
    const formFactors = <(String, Size, List<DisplayFeature>)>[
      ('narrow cover', _coverScreen, []),
      ('unfolded square', _unfoldedSquare, [_flatCreaseFeature]),
      ('book hinged', _bookSize, [_bookFeature]),
      ('clamshell tabletop', _tabletopFlip, [_flipTabletopFeature]),
    ];

    const locales = [
      Locale('en'),
      Locale('de'),
      Locale('ar'),
      Locale('ja'),
      Locale('tr'),
    ];

    for (final (formName, size, features) in formFactors) {
      for (final locale in locales) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$formName in $locale at ${scale}x has zero overflows', (
            tester,
          ) async {
            _setFoldableView(tester, size, displayFeatures: features);
            addTearDown(tester.view.reset);

            final recvOfferRepo = FakeRepository();
            final recvOfferVm = ReceiveViewModel(repository: recvOfferRepo)
              ..setInput('7-harbor-rocket');

            final widgets = <Widget>[
              HomeView(onSend: () {}, onReceive: () {}, onSettings: () {}),
              SendView(
                viewModel: SendViewModel(
                  repository: FakeRepository(),
                  fileSource: FakeFileSource(),
                )..addFakeFileForTest('Rapport annuel 2026.pdf'),
              ),
              ReceiveView(viewModel: recvOfferVm),
              SettingsView(
                settings: settings,
                version: '0.4.0-beta.1',
                background: const _Limits(),
              ),
              BackgroundSetupView(
                access: const _Limits(),
                firstRun: true,
                onDone: ({required skipped}) {},
              ),
            ];

            for (final w in widgets) {
              await tester.pumpWidget(
                _app(w, locale: locale, textScale: scale),
              );
              if (w is ReceiveView && !recvOfferRepo.connected.isCompleted) {
                unawaited(recvOfferVm.connect());
                recvOfferRepo.connected.complete(FakeOffer());
              }
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(
                tester.takeException(),
                isNull,
                reason:
                    'overflow on ${w.runtimeType} ($formName, $locale, ${scale}x)',
              );
            }
          });
        }
      }
    }
  });
}
