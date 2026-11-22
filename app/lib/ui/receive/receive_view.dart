// SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../core/adaptive.dart';
import '../core/common.dart';
import '../core/l10n.dart';
import '../core/mark.dart';
import '../core/theme.dart';
import 'receive_view_model.dart';

class ReceiveView extends StatefulWidget {
  const ReceiveView({super.key, required this.viewModel});

  final ReceiveViewModel viewModel;

  @override
  State<ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<ReceiveView> {
  late final _controller = TextEditingController(text: widget.viewModel.input);

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_showInput);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_showInput);
    _controller.dispose();
    super.dispose();
  }

  /// A link can fill in the code from outside the field (#445).
  void _showInput() {
    final input = widget.viewModel.input;
    if (_controller.text == input) return;
    _controller.value = TextEditingValue(
      text: input,
      selection: TextSelection.collapsed(offset: input.length),
    );
  }

  Future<bool> _confirmStop(BuildContext context) async {
    final l = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.cancelTransferTitle),
            content: Text(l.cancelTransferBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.keepGoing),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.stop),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final vm = widget.viewModel;
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        return PopScope(
          canPop: !vm.busy && vm.stage != ReceiveStage.offered,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              if (vm.stage != ReceiveStage.entering) vm.reset();
              _controller.clear();
              return;
            }
            if (vm.stage == ReceiveStage.offered) {
              await vm.decline();
              vm.reset();
              if (context.mounted) Navigator.pop(context);
              return;
            }
            if (await _confirmStop(context)) {
              vm.reset();
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: AppBar(title: Text(l.receiveTitle)),
            body: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(vm.stage),
                child: switch (vm.stage) {
                  ReceiveStage.entering => _Entering(
                    vm: vm,
                    controller: _controller,
                  ),
                  ReceiveStage.connecting => _Connecting(vm: vm),
                  ReceiveStage.offered => _Offered(vm: vm),
                  ReceiveStage.transferring => _Transferring(vm: vm),
                  ReceiveStage.done => _Done(vm: vm),
                  ReceiveStage.declined => _Message(
                    icon: Icons.block,
                    text: l.receiveDeclined,
                    onDone: () {
                      vm.reset();
                      Navigator.pop(context);
                    },
                  ),
                  ReceiveStage.failed => AdaptiveErrorView(
                    error: vm.error!,
                    onRetry: () {
                      vm.reset();
                      _controller.clear();
                    },
                  ),
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting({required this.vm});
  final ReceiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final mark = TotalDropMark(
      size: adaptiveMarkSize(context, 120),
      sending: true,
    );
    final status = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Announced(
          Text(
            l.receiveConnecting,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (vm.connectingCode case final code?) ...[
          Gap.s,
          // The code is English words, left to right in every language.
          Text(
            code,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ],
    );
    return AdaptivePaneLayout(
      splitFlatWide: false,
      compactBuilder: (_) => CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [mark, Gap.l, status],
        ),
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: mark,
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: status,
      ),
    );
  }
}

class _Entering extends StatelessWidget {
  const _Entering({required this.vm, required this.controller});
  final ReceiveViewModel vm;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;

    final codeField = TextField(
      controller: controller,
      autofocus: true,
      // The code is English words, left to right in every language.
      textDirection: TextDirection.ltr,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.go,
      style: theme.textTheme.headlineSmall,
      decoration: InputDecoration(
        labelText: l.receiveCodeLabel,
        hintText: l.receiveCodeHint,
        // The example code must never read as typed text.
        hintStyle: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
          fontWeight: FontWeight.w500,
        ),
        helperText: l.receiveCodeHelp,
        errorText: vm.showInvalid ? l.receiveCodeInvalid : null,
        // All of it, in every language and text size: at 200 % the
        // Japanese message ran past three lines and lost its end
        // (#480). errorText cannot go without a limit, so the limit is
        // one no message reaches; errorText, not the error widget,
        // because only it is read out with the field.
        errorMaxLines: 99,
        prefixIcon: const Icon(Icons.key_outlined),
        suffixIcon: KeepIconButtonVariant(
          child: IconButton(
            tooltip: l.receivePaste,
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final text = data?.text;
              if (text == null) return;
              final value = codeFromPaste(text);
              if (value.isEmpty) return;
              controller.text = value;
              vm.setInput(value);
            },
          ),
        ),
      ),
      onChanged: vm.setInput,
      onSubmitted: (_) => vm.connect(),
    );

    final connectButton = FilledButton.icon(
      onPressed: vm.input.trim().isEmpty ? null : vm.connect,
      icon: const Icon(Icons.link),
      label: Text(l.receiveConnect),
    );

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [
          Center(child: TotalDropMark(size: adaptiveMarkSize(context, 96))),
          Gap.l,
          codeField,
          Gap.l,
          connectButton,
          Gap.l,
          const SameNetworkNote(),
        ],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: TotalDropMark(size: adaptiveMarkSize(context, 96))),
            Gap.xl,
            const SameNetworkNote(),
          ],
        ),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [codeField, Gap.l, connectButton],
        ),
      ),
    );
  }
}

class _Offered extends StatelessWidget {
  const _Offered({required this.vm});
  final ReceiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final o = vm.offer!;
    final names = o.names;
    if (vm.isText) return _OfferedText(vm: vm);

    final offerSummary = <Widget>[
      Announced(Text(l.receiveOffer, style: theme.textTheme.headlineSmall)),
      Gap.s,
      Text(
        l.receiveOfferSummary(o.files, formatBytes(l, o.totalBytes)),
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Gap.m,
      const Divider(),
      for (final n in names.take(6)) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Gap.s,
              // Names come from the other side: hidden direction
              // characters are shown, not obeyed.
              Expanded(
                child: Text(
                  revealControls(n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
      ],
      if (names.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            l.receiveAndMore(names.length - 6),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
    ];

    final decision = <Widget>[
      VerificationWords(words: o.words),
      Gap.l,
      ButtonPair(
        outlined: PairedButton(
          safeL10n(context, 'receiveDecline').receiveDecline,
          vm.decline,
        ),
        filled: PairedButton(
          safeL10n(context, 'receiveAccept').receiveAccept,
          vm.accept,
        ),
      ),
    ];

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [...offerSummary, Gap.l, ...decision],
      ),
      primary: ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: offerSummary,
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: decision,
        ),
      ),
    );
  }
}

/// A text offered (#326): shown once accepted, never saved.
class _OfferedText extends StatelessWidget {
  const _OfferedText({required this.vm});
  final ReceiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final o = vm.offer!;

    final summary = <Widget>[
      Announced(Text(l.receiveOfferText, style: theme.textTheme.headlineSmall)),
      Gap.s,
      Text(
        formatBytes(l, o.totalBytes),
        style: theme.textTheme.titleMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Gap.s,
      Text(
        l.receiveOfferTextNote,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];

    final decision = <Widget>[
      VerificationWords(words: o.words),
      Gap.l,
      ButtonPair(
        outlined: PairedButton(
          safeL10n(context, 'receiveDecline').receiveDecline,
          vm.decline,
        ),
        filled: PairedButton(
          safeL10n(context, 'receiveAccept').receiveAccept,
          vm.accept,
        ),
      ),
    ];

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [...summary, Gap.l, ...decision],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: summary,
        ),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: decision,
        ),
      ),
    );
  }
}

class _Transferring extends StatelessWidget {
  const _Transferring({required this.vm});
  final ReceiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final progressColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: TotalDropMark(
            size: adaptiveMarkSize(context, 140),
            sending: true,
          ),
        ),
        Gap.l,
        Announced(
          Text(
            l.receiveReceiving,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Gap.m,
        TransferProgress(done: vm.done, total: vm.total),
      ],
    );
    if (vm.offer == null) {
      return AdaptivePaneLayout(
        splitFlatWide: false,
        compactBuilder: (_) => CenteredScroll(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
          child: progressColumn,
        ),
        primary: CenteredScroll(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
          child: TotalDropMark(
            size: adaptiveMarkSize(context, 120),
            sending: true,
          ),
        ),
        secondary: CenteredScroll(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Announced(
                Text(
                  l.receiveReceiving,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Gap.m,
              TransferProgress(done: vm.done, total: vm.total),
            ],
          ),
        ),
      );
    }
    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [
          progressColumn,
          Gap.l,
          VerificationWords(words: vm.offer!.words),
        ],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: progressColumn,
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: VerificationWords(words: vm.offer!.words),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.vm});
  final ReceiveViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final s = vm.summary;
    if (vm.receivedText case final text?) return _TextDone(vm: vm, text: text);

    final header = <Widget>[
      const Center(child: DoneBadge()),
      Gap.l,
      Announced(
        Text(
          l.receiveDone,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
      ),
      Gap.s,
      if (vm.folder != null)
        Text(
          l.receiveSaveTo(
            isolate(vm.folder!.replaceFirst('/storage/emulated/0/', '')),
          ),
          textAlign: TextAlign.center,
        ),
      if (s != null && s.filesFailed > 0) ...[
        Gap.s,
        Text(
          l.sendSomeFailed(s.filesFailed),
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ],
    ];

    final savedFiles = <Widget>[
      if (s != null)
        for (final p in s.saved)
          ListTile(
            leading: Icon(
              Icons.check,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              revealControls(p.split('/').last),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
    ];

    final doneButton = FilledButton(
      onPressed: () {
        vm.reset();
        Navigator.pop(context);
      },
      child: Text(l.done),
    );

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [...header, Gap.m, ...savedFiles, Gap.l, doneButton],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: header,
        ),
      ),
      secondary: ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        children: [...savedFiles, if (savedFiles.isNotEmpty) Gap.l, doneButton],
      ),
    );
  }
}

/// A text received (#326): shown as plain text with hidden characters
/// named, never saved. Copy text copies it exactly as it came.
class _TextDone extends StatelessWidget {
  const _TextDone({required this.vm, required this.text});
  final ReceiveViewModel vm;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final shown = shownText(text);
    final note = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // The text scrolls in its own box, at most half the screen high, and
    // the page scrolls when large type leaves no room.
    final boxHeight = MediaQuery.sizeOf(context).height / 2;

    Widget textBox({double? maxHeight}) {
      final box = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          // Plain text: nothing in it is a link or markup.
          child: SelectableText(shown.text),
        ),
      );
      if (maxHeight == null) return box;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: box,
      );
    }

    final headline = Announced(
      Text(
        l.receiveTextDone,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
      ),
    );

    final actionButtons = <Widget>[
      if (shown.short) ...[Text(l.receiveTextShortened, style: note), Gap.s],
      if (shown.hidden) ...[Text(l.receiveTextHidden, style: note), Gap.s],
      if (shown.short || shown.hidden) Gap.s,
      OutlinedButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l.textCopied)));
          }
        },
        icon: const Icon(Icons.copy),
        label: Text(l.copyText),
      ),
      Gap.s,
      FilledButton(
        onPressed: () {
          vm.reset();
          Navigator.pop(context);
        },
        child: Text(l.done),
      ),
    ];

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [
          const Center(child: DoneBadge()),
          Gap.l,
          headline,
          Gap.m,
          textBox(maxHeight: boxHeight),
          Gap.m,
          ...actionButtons,
        ],
      ),
      primary: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: DoneBadge()),
            Gap.m,
            headline,
            Gap.m,
            Expanded(child: textBox()),
          ],
        ),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: actionButtons,
        ),
      ),
      tabletopPrimary: Padding(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            headline,
            Gap.s,
            Expanded(child: textBox()),
          ],
        ),
      ),
      tabletopSecondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: actionButtons,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.onDone,
  });
  final IconData icon;
  final String text;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final iconWidget = Icon(
      icon,
      size: 56,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final label = Announced(
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    final doneButton = FilledButton(
      onPressed: onDone,
      child: Text(AppLocalizations.of(context).done),
    );

    return AdaptivePaneLayout(
      splitFlatWide: false,
      compactBuilder: (_) => CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [iconWidget, Gap.m, label, Gap.l, doneButton],
        ),
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [iconWidget, Gap.m, label],
        ),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [doneButton],
        ),
      ),
    );
  }
}
