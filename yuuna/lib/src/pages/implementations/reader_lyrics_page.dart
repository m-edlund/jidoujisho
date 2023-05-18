import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nowplaying/nowplaying.dart';
import 'package:remove_emoji/remove_emoji.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/creator.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// A page for [ReaderLyricsSource] which shows lyrics of current playing
/// media.
class ReaderLyricsPage extends BaseSourcePage {
  /// Create an instance of this tab page.
  const ReaderLyricsPage({
    super.item,
    super.key,
  });

  @override
  BaseSourcePageState createState() => _ReaderLyricsPageState();
}

/// A base class for providing all tabs in the main menu. In large part, this
/// was implemented to define shortcuts for common lengthy methods across UI
/// code.
class _ReaderLyricsPageState<ReaderLyricsPage> extends BaseSourcePageState {
  Orientation? lastOrientation;

  ReaderLyricsSource get source => ReaderLyricsSource.instance;

  /// Allows programmatic changing of the current text selection.
  final JidoujishoSelectableTextController _selectableTextController =
      JidoujishoSelectableTextController();

  @override
  void initState() {
    super.initState();
    source.overrideStream.listen((_) {
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    if (orientation != lastOrientation) {
      clearDictionaryResult();
      lastOrientation = orientation;
    }

    AsyncValue<bool> permissionGranted = ref.watch(lyricsPermissionsProvider);

    return permissionGranted.when(
      loading: buildLoading,
      error: (error, stack) => buildError(
        error: error,
        stack: stack,
        refresh: () {
          ref.invalidate(lyricsPermissionsProvider);
        },
      ),
      data: (permissionGranted) => buildPermissions(
        permissionGranted: permissionGranted,
      ),
    );
  }

  Widget buildPermissions({required bool permissionGranted}) {
    if (permissionGranted) {
      return buildTrackWhen();
    } else {
      return buildNeedPermission();
    }
  }

  Widget buildNeedPermission() {
    return Center(
      child: JidoujishoPlaceholderMessage(
        icon: Icons.error,
        message: t.lyrics_permission_required,
      ),
    );
  }

  Widget buildNoLyricsFound({required JidoujishoLyricsParameters parameters}) {
    return Center(
      child: JidoujishoPlaceholderMessage(
        icon: Icons.music_off,
        message: parameters.artist.isEmpty
            ? '${t.no_lyrics_found}\n『${parameters.title}』'
            : '${t.no_lyrics_found}\n『${parameters.title} - ${parameters.artist}』',
      ),
    );
  }

  Widget buildNoCurrentMedia() {
    return Center(
      child: JidoujishoPlaceholderMessage(
        icon: Icons.lyrics,
        message: t.no_current_media,
      ),
    );
  }

  Widget buildTrackWhen() {
    final track = ref.watch(lyricsStreamProvider);

    return track.when(
      loading: buildNoCurrentMedia,
      error: (error, stack) => buildError(
        error: error,
        stack: stack,
        refresh: () {
          ref.invalidate(lyricsStreamProvider);
        },
      ),
      data: (track) {
        if (source.isOverride) {
          return buildLyricsWhen(
            track: NowPlaying.instance.track,
            parameters: JidoujishoLyricsParameters(
              artist: source.overrideArtist!,
              title: source.overrideTitle!,
            ),
          );
        }

        if (track.artist == null || track.title == null) {
          return buildNoCurrentMedia();
        }

        JidoujishoLyricsParameters parameters = JidoujishoLyricsParameters(
          artist: track.artist!,
          title: track.title!,
        );

        return buildLyricsWhen(
          parameters: parameters,
          track: track,
        );
      },
    );
  }

  Widget buildLyricsWhen({
    required JidoujishoLyricsParameters parameters,
    required NowPlayingTrack track,
  }) {
    AsyncValue<JidoujishoLyrics> lyrics = ref.watch(lyricsProvider(parameters));
    return lyrics.when(
      loading: buildLoading,
      error: (error, stack) => buildError(
        error: error,
        stack: stack,
        refresh: () {
          ref.invalidate(lyricsProvider(parameters));
        },
      ),
      data: (lyrics) => buildLyrics(
        lyrics: lyrics,
        parameters: parameters,
        track: track,
      ),
    );
  }

  Widget buildLyrics({
    required JidoujishoLyrics lyrics,
    required JidoujishoLyricsParameters parameters,
    required NowPlayingTrack track,
  }) {
    ReaderLyricsSource source = ReaderLyricsSource.instance;

    if (lyrics.text == null) {
      return buildNoLyricsFound(parameters: parameters);
    }

    return Stack(
      children: [
        GestureDetector(
          onTap: clearDictionaryResult,
          child: RawScrollbar(
            thumbVisibility: true,
            thickness: 3,
            controller: ReaderMediaType.instance.scrollController,
            child: RawScrollbar(
              thumbVisibility: true,
              thickness: 3,
              controller: ReaderMediaType.instance.scrollController,
              child: SingleChildScrollView(
                controller: ReaderMediaType.instance.scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                primary: false,
                child: Padding(
                  padding: Spacing.of(context).insets.horizontal.extraBig,
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const Space.extraBig(),
                      const Space.big(),
                      if (!source.isOverride ||
                          (NowPlaying.instance.track.title ==
                                  parameters.title &&
                              NowPlaying.instance.track.artist ==
                                  parameters.artist))
                        Row(
                          children: [
                            if (track.hasImage && lyrics.includesArtist)
                              SizedBox(
                                height: 96,
                                width: 96,
                                child: Image(image: track.image!),
                              ),
                            if (track.hasImage && lyrics.includesArtist)
                              const Space.semiBig(),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    parameters.title,
                                    selectionControls: selectionControls,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (lyrics.includesArtist)
                                    SelectableText(
                                      parameters.artist,
                                      selectionControls: selectionControls,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      const Space.big(),
                      buildLyricsText(lyrics.text!),
                      const Space.big(),
                      Container(height: MediaQuery.of(context).size.height / 2)
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            const Space.extraBig(),
            Expanded(
              child: buildDictionary(),
            ),
          ],
        ),
      ],
    );
  }

  String _currentSelection = '';
  final FocusNode _lyricsFocusNode = FocusNode(skipTraversal: true);

  Widget buildLyricsText(String text) {
    text = RemoveEmoji().clean(text);
    return JidoujishoSelectableText.rich(
      TextSpan(children: getSubtitleSpans(text)),
      focusNode: _lyricsFocusNode,
      controller: _selectableTextController,
      selectionControls: selectionControls,
      onSelectionChanged: (selection, cause) {
        String textSelection = selection.textInside(text);
        _currentSelection = textSelection;
      },
    );
  }

  List<InlineSpan> getSubtitleSpans(String text) {
    List<InlineSpan> spans = [];

    text.runes.forEachIndexed((index, rune) {
      String character = String.fromCharCode(rune);
      spans.add(
        TextSpan(
            text: character,
            style: const TextStyle(fontSize: 22),
            recognizer: TapGestureRecognizer()
              ..onTapDown = (details) async {
                onTapDown(
                  character: character,
                  text: text,
                  index: index,
                  controller: _selectableTextController,
                  details: details,
                );
              }),
      );
    });

    return spans;
  }

  void onTapDown({
    required String text,
    required String character,
    required int index,
    required TapDownDetails details,
    required JidoujishoSelectableTextController controller,
  }) {
    bool wholeWordCondition =
        controller.selection.start <= index && controller.selection.end > index;

    if (wholeWordCondition && currentResult != null) {
      clearDictionaryResult();
      return;
    }

    double x = details.globalPosition.dx;
    double y = details.globalPosition.dy;

    late JidoujishoPopupPosition position;
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      if (y < MediaQuery.of(context).size.height / 2) {
        position = JidoujishoPopupPosition.bottomHalf;
      } else {
        position = JidoujishoPopupPosition.topHalf;
      }
    } else {
      if (x < MediaQuery.of(context).size.width / 2) {
        position = JidoujishoPopupPosition.rightHalf;
      } else {
        position = JidoujishoPopupPosition.leftHalf;
      }
    }

    String searchTerm = appModel.targetLanguage.getSearchTermFromIndex(
      text: text,
      index: index,
    );

    if (_currentSelection.isEmpty && character.trim().isNotEmpty) {
      /// If we cut off at a lone surrogate, offset the index back by 1. The
      /// selection meant to select the index before
      RegExp loneSurrogate = RegExp(
        '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]',
      );
      if (index != 0 && text.substring(index).startsWith(loneSurrogate)) {
        index = index - 1;
      }

      int whitespaceOffset = searchTerm.length - searchTerm.trimLeft().length;
      int offsetIndex =
          appModel.targetLanguage.getStartingIndex(text: text, index: index) +
              whitespaceOffset;
      int length = appModel.targetLanguage.getGuessHighlightLength(
        searchTerm: searchTerm,
      );

      controller.setSelection(
        offsetIndex,
        offsetIndex + length,
      );

      searchDictionaryResult(
        searchTerm: searchTerm,
        position: position,
      ).then((result) {
        length = appModel.targetLanguage.getFinalHighlightLength(
          result: currentResult,
          searchTerm: searchTerm,
        );

        controller.setSelection(offsetIndex, offsetIndex + length);
        JidoujishoTextSelection selection =
            appModel.targetLanguage.getSentenceFromParagraph(
          paragraph: text,
          index: index,
          startOffset: offsetIndex,
          endOffset: offsetIndex + length,
        );

        source.setCurrentSentence(
          selection: selection,
        );
      });
    } else {
      clearDictionaryResult();
      _currentSelection = '';
    }

    FocusScope.of(context).unfocus();
  }

  @override
  void clearDictionaryResult() {
    super.clearDictionaryResult();
    _selectableTextController.clearSelection();
    source.clearCurrentSentence();
  }

  @override
  MaterialTextSelectionControls get selectionControls =>
      JidoujishoTextSelectionControls(
        searchAction: onSearch,
        stashAction: onStash,
        shareAction: onShare,
        creatorAction: (text) async {
          await appModel.openCreator(
            creatorFieldValues: CreatorFieldValues(
              textValues: {
                SentenceField.instance: text,
                TermField.instance: '',
                ClozeBeforeField.instance: '',
                ClozeInsideField.instance: '',
                ClozeAfterField.instance: '',
              },
            ),
            killOnPop: false,
            ref: ref,
          );
        },
        allowCopy: true,
        allowSelectAll: false,
        allowCut: true,
        allowPaste: true,
      );
}
