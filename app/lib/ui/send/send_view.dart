// SPDX-FileCopyrightText: 2026 The TotalDrop Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../core/adaptive.dart';
import '../core/common.dart';
import '../core/l10n.dart';
import '../core/mark.dart';
import '../core/theme.dart';
import 'send_view_model.dart';

class SendView extends StatelessWidget {
  const SendView({super.key, required this.viewModel});

  final SendViewModel viewModel;

  Future<bool> _confirmStop(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final stop = await showDialog<bool>(
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
    );
    return stop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final vm = viewModel;
        final reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        return PopScope(
          canPop: !vm.busy,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) {
              if (vm.stage != SendStage.picking) {
                vm.reset();
              } else {
                // Leaving the wait ends it: the shares stop, and what
                // was chosen before stays. A text being written goes.
                vm.cancelShares();
                vm.leaveText();
              }
              return;
            }
            if (await _confirmStop(context)) {
              vm.reset();
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: Scaffold(
            appBar: AppBar(title: Text(vm.textMode ? l.sendText : l.sendTitle)),
            body: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey((vm.stage, vm.copying || vm.sharing)),
                child: switch (vm.stage) {
                  // The picker copies the chosen files into the app
                  // cache before it hands them over (#269).
                  SendStage.picking when vm.copying || vm.sharing => _Centered(
                    logo: TotalDropMark(
                      size: adaptiveMarkSize(context, 120),
                      sending: true,
                    ),
                    text: l.sendPreparing,
                    // A share's copy can be stopped; the picker's
                    // belongs to the picker.
                    action: vm.sharing && !vm.copying
                        ? TextButton(
                            onPressed: vm.cancelShares,
                            child: Text(l.cancel),
                          )
                        : null,
                  ),
                  SendStage.picking when vm.textMode => _TextPicking(vm: vm),
                  SendStage.picking => _Picking(vm: vm),
                  SendStage.preparing => _Centered(
                    logo: TotalDropMark(
                      size: adaptiveMarkSize(context, 120),
                      sending: true,
                    ),
                    text: l.sendPreparing,
                  ),
                  SendStage.waiting => _Waiting(vm: vm),
                  SendStage.connected => _Connected(vm: vm),
                  SendStage.transferring => _Transferring(vm: vm),
                  SendStage.done => _Done(vm: vm),
                  SendStage.failed => AdaptiveErrorView(
                    error: vm.error!,
                    onRetry: vm.start,
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

class _Centered extends StatelessWidget {
  const _Centered({required this.logo, required this.text, this.action});
  final Widget logo;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final label = Announced(
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
    return AdaptivePaneLayout(
      splitFlatWide: false,
      compactBuilder: (_) => CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            Gap.l,
            label,
            if (action case final a?) ...[Gap.l, a],
          ],
        ),
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: logo,
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            if (action case final a?) ...[Gap.l, a],
          ],
        ),
      ),
    );
  }
}

class _Picking extends StatelessWidget {
  const _Picking({required this.vm});
  final SendViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;

    if (vm.files.isEmpty) {
      final prompt = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.upload_file_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          Gap.m,
          Text(
            l.sendEmpty,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          Gap.s,
          Text(
            l.sendEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      final actions = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.addFailed) ...[
            const _AddFailed(textAlign: TextAlign.center),
            Gap.m,
          ],
          FilledButton.icon(
            onPressed: vm.addFiles,
            icon: const Icon(Icons.attach_file),
            label: Text(l.sendAddFiles),
          ),
          Gap.s,
          OutlinedButton.icon(
            onPressed: () => vm.setTextMode(true),
            icon: const Icon(Icons.notes),
            label: Text(l.sendText),
          ),
        ],
      );

      // One screen, one job: the only action is choosing files. With the
      // largest text the page scrolls instead of running off (#322).
      return AdaptivePaneLayout(
        compactBuilder: (_) => CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const Spacer(), prompt, const Spacer(), actions],
                ),
              ),
            ),
          ],
        ),
        primary: CenteredScroll(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
          child: prompt,
        ),
        secondary: CenteredScroll(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
          child: actions,
        ),
      );
    }

    Widget fileList() => ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
      itemCount: vm.files.length + 1,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) {
        if (i == vm.files.length) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: vm.addFiles,
                icon: const Icon(Icons.add),
                label: Text(l.sendAddFiles),
              ),
              if (vm.addFailed)
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                  child: _AddFailed(textAlign: TextAlign.start),
                ),
            ],
          );
        }
        final f = vm.files[i];
        return ListTile(
          leading: Icon(
            Icons.insert_drive_file_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            formatBytes(l, f.size),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          trailing: KeepIconButtonVariant(
            child: IconButton(
              tooltip: l.sendRemove,
              icon: const Icon(Icons.close),
              onPressed: () => vm.remove(f),
            ),
          ),
        );
      },
    );

    Widget startControls() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.sendStrongCode),
          subtitle: Text(l.sendStrongCodeHint),
          value: vm.strong,
          onChanged: vm.setStrong,
        ),
        Gap.s,
        FilledButton.icon(
          onPressed: vm.start,
          icon: const Icon(Icons.key_outlined),
          // Read out when the list appears after the picker's copy
          // and when it changes, so a screen reader is not left
          // silent where "Add files" was (#271).
          label: Announced(
            Text(
              '${l.sendCreateCode} · ${l.itemsAndSize(vm.files.length, formatBytes(l, vm.totalSize))}',
            ),
          ),
        ),
      ],
    );

    return AdaptivePaneLayout(
      compactBuilder: (_) => Column(
        children: [
          Expanded(child: fileList()),
          const Divider(),
          // Pinned under the list. With the largest text it takes at most
          // half the screen and scrolls itself, so the list keeps its room
          // (#322).
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height / 2,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
              child: startControls(),
            ),
          ),
        ],
      ),
      primary: fileList(),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: startControls(),
      ),
    );
  }
}

/// A text to send instead of files (#326): typed, pasted, shared from
/// another app or selected there. What is sent is the text in the box,
/// as UTF-8; a text too long to edit is shown in part and sent whole.
class _TextPicking extends StatefulWidget {
  const _TextPicking({required this.vm});
  final SendViewModel vm;

  @override
  State<_TextPicking> createState() => _TextPickingState();
}

class _TextPickingState extends State<_TextPicking> {
  late final _controller = TextEditingController(text: _boxText);

  String get _boxText {
    final vm = widget.vm;
    return vm.bigText ? vm.text.substring(0, _cut(vm.text)) : vm.text;
  }

  /// Not inside a character made of two UTF-16 units.
  static int _cut(String t) {
    final end = shownTextChars;
    final last = t.codeUnitAt(end - 1);
    return last >= 0xD800 && last <= 0xDBFF ? end - 1 : end;
  }

  @override
  void didUpdateWidget(_TextPicking old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The box follows a text that came from elsewhere (clipboard, share).
  void _sync() {
    final want = _boxText;
    if (_controller.text != want) {
      _controller.value = TextEditingValue(
        text: want,
        selection: TextSelection.collapsed(offset: want.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vm = widget.vm;
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final notice = switch (vm.textNotice) {
      TextNotice.clipboardEmpty => l.sendClipboardEmpty,
      TextNotice.clipboardKept => l.sendClipboardKept,
      TextNotice.none when vm.textTooLong => l.sendTextTooLong(
        formatBytes(l, vm.maxTextBytes),
      ),
      TextNotice.none when vm.bigText => l.sendTextShortened,
      TextNotice.none => null,
    };
    final warn = vm.textTooLong || vm.textNotice != TextNotice.none;
    // The box shows hidden characters as the system draws them, which is
    // often not at all: the screen names them (#326).
    final hidden = vm.text.isNotEmpty && shownText(vm.text).hidden;

    Widget editorField({double minHeight = 160}) => ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: TextField(
        controller: _controller,
        // A long text cannot be edited, only taken away.
        readOnly: vm.bigText,
        autofocus: vm.text.isEmpty,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(
          hintText: l.sendTextHint,
          border: const OutlineInputBorder(),
        ),
        onChanged: vm.setText,
      ),
    );

    Widget controls({required bool showTopDivider}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          Announced(
            Text(
              notice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: warn
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Gap.s,
        ],
        if (hidden) ...[
          Announced(
            Text(
              l.sendTextHidden,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Gap.s,
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (vm.text.isEmpty)
              OutlinedButton.icon(
                onPressed: vm.pasteClipboard,
                icon: const Icon(Icons.content_paste),
                label: Text(l.receivePaste),
              )
            else
              OutlinedButton.icon(
                onPressed: () => vm.setText(''),
                icon: const Icon(Icons.clear),
                label: Text(l.sendRemove),
              ),
            if (vm.text.isEmpty)
              OutlinedButton.icon(
                onPressed: () {
                  vm.setTextMode(false);
                  if (vm.files.isEmpty) vm.addFiles();
                },
                icon: const Icon(Icons.attach_file),
                label: Text(l.sendAddFiles),
              ),
          ],
        ),
        if (showTopDivider) const Divider(height: 24) else Gap.m,
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.sendStrongCode),
          subtitle: Text(l.sendStrongCodeHint),
          value: vm.strong,
          onChanged: vm.setStrong,
        ),
        Gap.s,
        FilledButton.icon(
          onPressed: vm.canStart ? vm.start : null,
          icon: const Icon(Icons.key_outlined),
          label: Text(
            vm.text.isEmpty
                ? l.sendCreateCode
                : '${l.sendCreateCode} · ${formatBytes(l, vm.textBytes)}',
          ),
        ),
      ],
    );

    // The box takes the room left; with the keyboard up or large type,
    // the page scrolls instead of overflowing.
    return AdaptivePaneLayout(
      compactBuilder: (_) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editorField()),
                  Gap.s,
                  controls(showTopDivider: true),
                ],
              ),
            ),
          ),
        ],
      ),
      primary: Padding(
        padding: EdgeInsets.fromLTRB(pad, 16, pad, 24),
        child: editorField(minHeight: 120),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: controls(showTopDivider: false),
      ),
    );
  }
}

/// Why the picker came back with nothing (#271).
class _AddFailed extends StatelessWidget {
  const _AddFailed({required this.textAlign});
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Announced(
      Text(
        AppLocalizations.of(context).sendAddFailed,
        textAlign: textAlign,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.vm});
  final SendViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final code = vm.code ?? '';

    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.sendCopied)));
      }
    }

    // Isolated, the code keeps its order in a right-to-left sentence;
    // pasted back, the receiver drops the marks.
    Future<void> share() async {
      await SharePlus.instance.share(
        ShareParams(text: l.sendShareText(isolate(code))),
      );
    }

    Widget codeText() => Semantics(
      attributedLabel: AttributedString(
        code,
        attributes: [
          LocaleStringAttribute(
            range: TextRange(start: 0, end: code.length),
            locale: const Locale('en'),
          ),
        ],
      ),
      excludeSemantics: true,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SelectableText(
          code,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineLarge,
        ),
      ),
    );

    Widget codeCard({required bool includeButtons}) => Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              l.sendYourCode,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Gap.s,
            // English words, left to right in every language.
            // Spoken with an English voice; the Copy button below copies it.
            codeText(),
            if (includeButtons) ...[
              Gap.m,
              ButtonPair(
                spacing: 8,
                outlined: PairedButton(l.sendCopy, copy, icon: Icons.copy),
                filled: PairedButton(l.sendShare, share, icon: Icons.share),
              ),
            ],
          ],
        ),
      ),
    );

    final waitingStatus = Announced(
      Text(
        l.sendWaiting,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final codeHint = Text(
      l.sendCodeHint,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge,
    );

    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [
          Center(
            child: TotalDropMark(
              size: adaptiveMarkSize(context, 120),
              sending: true,
            ),
          ),
          Gap.s,
          waitingStatus,
          Gap.l,
          // The code is the content; the frame stays quiet.
          codeCard(includeButtons: true),
          Gap.m,
          codeHint,
          Gap.xl,
          const SameNetworkNote(),
        ],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TotalDropMark(
                size: adaptiveMarkSize(context, 120),
                sending: true,
              ),
            ),
            Gap.m,
            waitingStatus,
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
          children: [codeCard(includeButtons: true), Gap.m, codeHint],
        ),
      ),
      // Tabletop / Flex posture: show the readable code on the tilted upper
      // display half while keeping Copy/Share controls on the lower half.
      tabletopPrimary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TotalDropMark(
                size: adaptiveMarkSize(context, 88),
                sending: true,
              ),
            ),
            Gap.s,
            waitingStatus,
            Gap.m,
            codeCard(includeButtons: false),
          ],
        ),
      ),
      tabletopSecondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ButtonPair(
              spacing: 8,
              outlined: PairedButton(l.sendCopy, copy, icon: Icons.copy),
              filled: PairedButton(l.sendShare, share, icon: Icons.share),
            ),
            Gap.m,
            codeHint,
            Gap.l,
            const SameNetworkNote(),
          ],
        ),
      ),
    );
  }
}

/// The receiver came and decides: the words to compare, nothing sent yet.
class _Connected extends StatelessWidget {
  const _Connected({required this.vm});
  final SendViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final status = Announced(
      Text(
        l.sendWaitingAccept,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
    return AdaptivePaneLayout(
      compactBuilder: (_) => ListView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        children: [
          Center(
            child: TotalDropMark(
              size: adaptiveMarkSize(context, 120),
              sending: true,
            ),
          ),
          Gap.l,
          VerificationWords(words: vm.words),
          Gap.m,
          status,
        ],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TotalDropMark(size: adaptiveMarkSize(context, 120), sending: true),
            Gap.l,
            status,
          ],
        ),
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: VerificationWords(words: vm.words),
      ),
    );
  }
}

class _Transferring extends StatelessWidget {
  const _Transferring({required this.vm});
  final SendViewModel vm;

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
            l.sendSending,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Gap.m,
        TransferProgress(done: vm.done, total: vm.total),
      ],
    );
    if (vm.words.isEmpty) {
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
                  l.sendSending,
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
          VerificationWords(words: vm.words),
        ],
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: progressColumn,
      ),
      secondary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: VerificationWords(words: vm.words),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.vm});
  final SendViewModel vm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pad = AdaptiveMetrics.of(context).horizontalPadding;
    final s = vm.summary;

    final details = <Widget>[
      Announced(
        Text(
          l.sendDone,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
      ),
      Gap.s,
      if (vm.textMode)
        Text(l.sendTextDone, textAlign: TextAlign.center)
      else if (s != null) ...[
        Text(l.sendDoneBody(s.filesOk), textAlign: TextAlign.center),
        if (s.filesFailed > 0) ...[
          Gap.s,
          Text(
            l.sendSomeFailed(s.filesFailed),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    ];

    final doneButton = FilledButton(
      onPressed: () {
        vm.reset();
        Navigator.pop(context);
      },
      child: Text(l.done),
    );

    return AdaptivePaneLayout(
      splitFlatWide: false,
      compactBuilder: (_) => CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: DoneBadge()),
            Gap.l,
            ...details,
            Gap.xl,
            doneButton,
          ],
        ),
      ),
      primary: CenteredScroll(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: DoneBadge()),
            Gap.m,
            ...details,
          ],
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
