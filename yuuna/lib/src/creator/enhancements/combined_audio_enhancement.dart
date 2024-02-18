import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kana_kit/kana_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yuuna/creator.dart';
import 'package:yuuna/models.dart';
import 'dart:convert';

import 'package:yuuna/language.dart';
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'package:http/http.dart' as http;

/// An enhancement for fetching audio from Combined.
class CombinedAudioEnhancement extends AudioEnhancement {
  /// Initialise this enhancement with the hardset parameters.
  CombinedAudioEnhancement()
      : super(
          uniqueKey: key,
          label: 'Combined Audio',
          description:
              'Search for matching word pronunciations from Forvo and JapanesePod101.',
          icon: Icons.playlist_add_check_circle,
          field: AudioField.instance,
        );

  final List<String> _prioritizedForvoContributers = [
    'roche',
    'strawberrybrown',
    'kiiro',
    'mezashi',
    'ryomasakamoto',
    'skent',
  ];

  /// Used to identify this enhancement and to allow a constant value for the
  /// default mappings value of [AnkiMapping].
  static const String key = 'combined_audio';

  final KanaKit _kanaKit = const KanaKit();

  final Map<String, List<ForvoResult>> _forvoCache = {};

  /// Client used to communicate with Forvo.
  final http.Client _client = http.Client();

  @override
  Future<void> enhanceCreatorParams({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
    required CreatorModel creatorModel,
    required EnhancementTriggerCause cause,
  }) async {
    AudioExportField audioField = field as AudioExportField;
    String? searchTerm;

    if (cause != EnhancementTriggerCause.auto) {
      searchTerm = audioField.getSearchTermWithFallback(
        appModel: appModel,
        creatorModel: creatorModel,
        fallbackSearchTerms: [
          TermField.instance,
          ReadingField.instance,
        ],
      );
    } else {
      searchTerm = creatorModel.getFieldController(TermField.instance).text;

      if (searchTerm.trim().isEmpty) {
        return;
      }
    }

    await audioField.setAudio(
      appModel: appModel,
      creatorModel: creatorModel,
      searchTerm: searchTerm,
      newAutoCannotOverride: false,
      cause: cause,
      generateAudio: () async {
        String reading =
            creatorModel.getFieldController(ReadingField.instance).text;
        return fetchAudio(
          appModel: appModel,
          context: context,
          term: searchTerm!,
          reading: reading,
        );
      },
    );
  }

  @override
  Future<File?> fetchAudio({
    required AppModel appModel,
    required BuildContext context,
    required String term,
    required String reading,
  }) async {
    List<ForvoResult> results = await _getForvoResults(
      appModel: appModel,
      searchTerm: term,
    );

    String temporaryDirectoryPath = (await getTemporaryDirectory()).path;
    String temporaryFileName =
        'jidoujisho-${DateFormat('yyyyMMddTkkmmss').format(DateTime.now())}';

    String filename = '$temporaryDirectoryPath/$temporaryFileName';

    var resultContributors = results.map((e) => e.contributor);
    var bestContributor = _prioritizedForvoContributers
        .where(
            (priC) => resultContributors.any((resC) => resC.startsWith(priC)))
        .firstOrNull;

    bool prioritizeForvo = bestContributor != null;

    File? jpPodFile = prioritizeForvo
        ? null
        : await _fetchJapanesePod101Audio(
            term: term,
            reading: reading,
            filename: filename,
          );

    // If the jpod file is not null it means there are no prioritized forvo
    // contributors and jpod had the audio
    if (jpPodFile != null) {
      return jpPodFile;
    }

    // If there are no forvo results, there is no audio anywhere and we give up
    if (results.isEmpty) {
      return null;
    }

    File file = File(filename);

    var bestResult = bestContributor != null
        ? results.firstWhereOrNull(
                (element) => element.contributor.startsWith(bestContributor)) ??
            results.first
        : results.first;

    File networkFile =
        await DefaultCacheManager().getSingleFile(bestResult.audioUrl);
    networkFile.copySync(file.path);

    return file;
  }

  Future<File?> _fetchJapanesePod101Audio({
    required String term,
    required String reading,
    required String filename,
  }) async {
    late String audioUrl;

    if (_kanaKit.isKana(term)) {
      audioUrl =
          'http://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kana=$term';
    } else {
      audioUrl =
          'http://assets.languagepod101.com/dictionary/japanese/audiomp3.php?kanji=$term&kana=$reading';
    }

    File file = File(filename);
    try {
      File networkFile = await DefaultCacheManager().getSingleFile(audioUrl);

      if (networkFile.readAsBytesSync().lengthInBytes == 52288) {
        return null;
      }
      networkFile.copySync(file.path);
    } catch (e) {
      return null;
    }

    return file;
  }

  /// Return a list of pronunciations from a search term.
  Future<List<ForvoResult>> _getForvoResults(
      {required AppModel appModel, required String searchTerm}) async {
    Codec<String, String> stringToBase64Url = utf8.fuse(base64Url);
    Language language = appModel.targetLanguage;
    String cacheKey = '${language.languageCode}/$searchTerm';

    List<ForvoResult> results = [];
    if (_forvoCache[cacheKey] != null) {
      results = _forvoCache[cacheKey]!;
    } else {
      http.Response response =
          await _client.get(Uri.parse('https://forvo.com/word/$searchTerm/'));
      var document = parser.parse(response.body);

      try {
        String className = '';

        // Language Customizable
        if (appModel.targetLanguage is JapaneseLanguage) {
          className = 'pronunciations-list-ja';
        } else if (appModel.targetLanguage is EnglishLanguage) {
          className = 'pronunciations-list-en_usa';
        }

        List<dom.Element> liElements = document
            .getElementsByClassName(className)
            .first
            .children
            .where((element) =>
                element.localName == 'li' &&
                element.children.first.id.startsWith('play_'))
            .toList();

        results = liElements.map((element) {
          String onClick = element.children[0].attributes['onclick']!;
          String? contributor = element.children[1].attributes['data-p2'];

          if (contributor == null) {
            element.children
                .where((child) =>
                    child.className == 'more' || child.className == 'from')
                .toList()
                .forEach((child) => child.remove());

            contributor = element.text
                .replaceAll(
                    RegExp(r'[\s\S]*?(?=Pronunciation by)Pronunciation by'), '')
                .trim();
          }

          String onClickCut = onClick.substring(onClick.indexOf(',') + 2);
          String base64 = onClickCut.substring(0, onClickCut.indexOf("'"));

          String fileUrl = stringToBase64Url.decode(base64);

          String audioUrl = 'https://audio.forvo.com/mp3/$fileUrl';

          return ForvoResult(
            audioUrl: audioUrl,
            contributor: contributor,
          );
        }).toList();

        _forvoCache[cacheKey] = results;
      } catch (error) {
        debugPrint('$error');
      }
    }

    return results;
  }
}
