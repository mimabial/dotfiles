import contextlib
import io
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

MEDIA_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MEDIA_DIR))

import autotag
from autotag import (
    CACHE_MISS_TTL,
    CACHE_SUCCESS_TTL,
    DEEZER_COOLDOWN,
    RateLimiter,
    ResolutionCache,
    Unidentified,
    album_context,
    candidate_agrees,
    derive_candidates,
    drop_redundant_feat,
    first_artist_fallbacks,
    filename_credit_loss,
    from_acoustid,
    from_itunes,
    from_musicbrainz,
    match_score,
    missing_credit_names,
    prepare_metadata,
    recovered_youtube_artist,
    resolve,
    restore_youtube_credit_tags,
    search_variants,
    split_featured_title,
    youtube_credit_metadata,
)


class AlbumMatchingTests(unittest.TestCase):
    @patch("autotag.http_get")
    def test_itunes_prefers_requested_album_over_single(self, http_get):
        http_get.return_value.json.return_value = {
            "results": [
                {
                    "trackId": 1,
                    "artistName": "Didi B",
                    "trackName": "Holiday Season",
                    "collectionName": "Holiday Season - Single",
                    "trackNumber": 1,
                    "trackCount": 1,
                    "artworkUrl100": "https://example.test/single/100x100bb.jpg",
                },
                {
                    "trackId": 2,
                    "artistName": "Didi B",
                    "trackName": "Holiday Season",
                    "collectionName": "DIYILEM & BAZARHOFF : GENIUS",
                    "trackNumber": 7,
                    "trackCount": 9,
                    "artworkUrl100": "https://example.test/album/100x100bb.jpg",
                },
            ]
        }

        result = from_itunes(
            "Didi B",
            "Holiday Season",
            RateLimiter(0),
            0.6,
            "DIYILEM & BAZARHOFF: GENIUS",
        )

        self.assertEqual(result["album"], "DIYILEM & BAZARHOFF : GENIUS")
        self.assertEqual(result["tracknumber"], "7/9")
        self.assertIn("/album/", result["artwork_url"])

    @patch("autotag.http_get")
    def test_itunes_rejects_unrelated_dj_mix_artwork(self, http_get):
        http_get.return_value.json.return_value = {
            "results": [
                {
                    "trackId": 1,
                    "artistName": "Didi B & Naira Marley",
                    "trackName": "FATUMATA (Mixed)",
                    "collectionName": "Afrobeats Life Of The Party 2025 (DJ Mix)",
                    "collectionArtistName": "Dj Boat",
                    "artworkUrl100": "https://example.test/mix/100x100bb.jpg",
                }
            ]
        }

        with self.assertRaisesRegex(Unidentified, "requested album"):
            from_itunes(
                "Didi B, Naira Marley",
                "FATÚMATA",
                RateLimiter(0),
                0.6,
                "DIYILEM & BAZARHOFF: GENIUS",
            )

    def test_directory_album_overrides_single_tag(self):
        path = Path("/music/Didi B/DIYILEM & BAZARHOFF GENIUS/song.opus")
        album, key = album_context(
            path,
            {"album": ["Holiday Season"], "artist": ["Didi B"]},
            Path("/music"),
        )

        self.assertEqual(album, "DIYILEM & BAZARHOFF GENIUS")
        self.assertTrue(key)

    @patch("autotag.from_itunes")
    def test_delisted_single_uses_reissue_without_mixing_release_tags(self, itunes):
        def result(_artist, _title, _limiter, _threshold, album=""):
            if album:
                raise Unidentified("no itunes match on requested album")
            return {
                "artist": "Shan'L", "title": "Tchizabengue",
                "album": "Eklektik 2.0", "date": "2020", "tracknumber": "10/24",
                "genre": "Worldwide", "artwork_url": "https://example.test/reissue.jpg",
            }

        itunes.side_effect = result
        args = SimpleNamespace(
            no_fingerprint=True, min_score=0.5, provider_order=["itunes"],
            fallback=True, min_similarity=0.6,
        )
        tags = {
            "artist": ["Shan'L"], "title": ["Tchizabengué"],
            "album": ["Tchizabengué"], "date": ["20180426"],
        }
        result = resolve(
            Path("/music/Shan'L/Shan'L - Tchizabengué.opus"), Path("/music"), args,
            {"itunes": RateLimiter(0)}, "", tags,
        )

        self.assertEqual(
            {key: result[key] for key in ("artist", "title", "album", "date", "tracknumber")},
            {"artist": "Shan'L", "title": "Tchizabengué", "album": "Tchizabengué",
             "date": "20180426", "tracknumber": "1/1"},
        )
        self.assertEqual(result["artwork_url"], "")
        self.assertEqual(itunes.call_count, 2)


class CachePolicyTests(unittest.TestCase):
    def test_requested_expirations(self):
        self.assertEqual(CACHE_SUCCESS_TTL, 99 * 24 * 60 * 60)
        self.assertEqual(CACHE_MISS_TTL, 60 * 60)
        self.assertEqual(DEEZER_COOLDOWN, 60 * 60)


class ResolutionCacheTests(unittest.TestCase):
    @staticmethod
    def args():
        return SimpleNamespace(
            no_fingerprint=False,
            min_score=0.5,
            provider_order=["itunes"],
            fallback=True,
            min_similarity=0.6,
        )

    def test_batches_resolution_writes_until_flush(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "cache.sqlite3"
            cache = ResolutionCache(path)
            cache.put("song", {"identified": True}, CACHE_SUCCESS_TTL)

            with contextlib.closing(sqlite3.connect(path)) as observer:
                count_before = observer.execute(
                    "SELECT count(*) FROM resolutions"
                ).fetchone()[0]
            cache.flush()
            with contextlib.closing(sqlite3.connect(path)) as observer:
                count_after = observer.execute(
                    "SELECT count(*) FROM resolutions"
                ).fetchone()[0]
            cache.close()

        self.assertEqual(count_before, 0)
        self.assertEqual(count_after, 1)

    @patch("autotag.from_itunes")
    def test_reuses_success_without_calling_provider_again(self, from_itunes):
        from_itunes.return_value = {"artist": "Main", "title": "Song"}
        tags = {"artist": ["Main"], "title": ["Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / "Main - Song.opus"
            song.write_bytes(b"audio")
            cache = ResolutionCache(root / "cache.sqlite3")
            self.addCleanup(cache.close)

            first = resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
            )
            second = resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
            )

        self.assertEqual(first, second)
        self.assertEqual(from_itunes.call_count, 1)
        self.assertEqual(cache.hits, 1)

    @patch("autotag.from_itunes", side_effect=Unidentified("no itunes match"))
    def test_reuses_catalog_miss_without_calling_provider_again(self, from_itunes):
        tags = {"artist": ["Main"], "title": ["Missing Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / "Main - Missing Song.opus"
            song.write_bytes(b"audio")
            cache = ResolutionCache(root / "cache.sqlite3")
            self.addCleanup(cache.close)

            with self.assertRaisesRegex(Unidentified, r"no itunes match"):
                resolve(
                    song,
                    root,
                    self.args(),
                    {"itunes": RateLimiter(0)},
                    "",
                    tags,
                    cache,
                )
            with self.assertRaisesRegex(Unidentified, r"\[cached\]"):
                resolve(
                    song,
                    root,
                    self.args(),
                    {"itunes": RateLimiter(0)},
                    "",
                    tags,
                    cache,
                )

        self.assertEqual(from_itunes.call_count, 1)
        self.assertEqual(cache.hits, 1)

    @patch("autotag.from_itunes")
    def test_changed_file_invalidates_cached_resolution(self, from_itunes):
        from_itunes.return_value = {"artist": "Main", "title": "Song"}
        tags = {"artist": ["Main"], "title": ["Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / "Main - Song.opus"
            song.write_bytes(b"audio")
            cache = ResolutionCache(root / "cache.sqlite3")
            self.addCleanup(cache.close)

            resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
            )
            song.write_bytes(b"different audio")
            resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
            )

        self.assertEqual(from_itunes.call_count, 2)

    @patch("autotag.from_itunes")
    def test_refresh_bypasses_cached_resolution(self, from_itunes):
        from_itunes.return_value = {"artist": "Main", "title": "Song"}
        tags = {"artist": ["Main"], "title": ["Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / "Main - Song.opus"
            song.write_bytes(b"audio")
            cache = ResolutionCache(root / "cache.sqlite3")
            self.addCleanup(cache.close)

            resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
            )
            resolve(
                song,
                root,
                self.args(),
                {"itunes": RateLimiter(0)},
                "",
                tags,
                cache,
                refresh_cache=True,
            )

        self.assertEqual(from_itunes.call_count, 2)


class AcoustIDTests(unittest.TestCase):
    @patch("autotag.http_get")
    @patch("autotag.fingerprint", return_value=(180, "fingerprint"))
    def test_requests_space_separated_metadata(self, _fingerprint, http_get):
        http_get.return_value.json.return_value = {"status": "ok", "results": []}

        with self.assertRaisesRegex(Unidentified, "no acoustid match"):
            from_acoustid(Path("/music/song.opus"), "key", RateLimiter(0), 0.8)

        self.assertEqual(
            http_get.call_args.args[1]["meta"],
            "recordings releasegroups compress",
        )

    @patch("autotag.http_get")
    @patch("autotag.fingerprint", return_value=(180, "fingerprint"))
    def test_selects_recording_that_agrees_with_local_identity(
        self, _fingerprint, http_get
    ):
        http_get.return_value.json.return_value = {
            "status": "ok",
            "results": [
                {
                    "score": 0.99,
                    "recordings": [
                        {
                            "title": "Unrelated Song",
                            "artists": [{"name": "Other Artist"}],
                        },
                        {
                            "title": "Song",
                            "artists": [{"name": "Main"}, {"name": "Guest"}],
                        },
                    ],
                },
            ],
        }

        result = from_acoustid(
            Path("/music/song.opus"),
            "key",
            RateLimiter(0),
            0.5,
            [("Main", "Song (feat. Guest)")],
        )

        self.assertEqual(result["artist"], "Main, Guest")
        self.assertEqual(result["title"], "Song")

    @patch("autotag.http_get")
    @patch("autotag.fingerprint", return_value=(180, "fingerprint"))
    def test_rejects_unrelated_recording_even_at_high_fingerprint_score(
        self, _fingerprint, http_get
    ):
        http_get.return_value.json.return_value = {
            "status": "ok",
            "results": [
                {
                    "score": 0.99,
                    "recordings": [
                        {
                            "title": "Unrelated Song",
                            "artists": [{"name": "Other Artist"}],
                        },
                    ],
                },
            ],
        }

        with self.assertRaisesRegex(Unidentified, "no acoustid match"):
            from_acoustid(
                Path("/music/song.opus"),
                "key",
                RateLimiter(0),
                0.5,
                [("Main", "Song")],
            )


class FeatureCreditIdentityTests(unittest.TestCase):
    def test_extracts_bracketed_and_plain_trailing_features(self):
        self.assertEqual(
            split_featured_title("Song (feat. Guest)"),
            ("Song", "Guest"),
        )
        self.assertEqual(
            split_featured_title("Song ft. Guest"),
            ("Song", "Guest"),
        )

    def test_feature_can_move_from_title_to_artist_credit(self):
        self.assertTrue(
            candidate_agrees(
                "Main, Guest",
                "Song",
                "Main",
                "Song (feat. Guest)",
            )
        )
        self.assertEqual(
            match_score(
                "Main, Guest",
                "Song",
                "Main",
                "Song (feat. Guest)",
            ),
            1.0,
        )

    def test_explicit_feature_does_not_match_solo_recording(self):
        self.assertFalse(
            candidate_agrees(
                "Main",
                "Song",
                "Main",
                "Song (feat. Guest)",
            )
        )

    def test_provider_title_can_carry_the_feature(self):
        self.assertTrue(
            candidate_agrees(
                "Main",
                "Song (feat. Guest)",
                "Main, Guest",
                "Song",
            )
        )

    def test_searches_both_provider_credit_layouts(self):
        self.assertEqual(
            search_variants("Main", "Song (feat. Guest)"),
            [
                ("Main", "Song (feat. Guest)"),
                ("Main, Guest", "Song"),
            ],
        )

    def test_equivalent_filename_and_tag_candidates_are_deduplicated(self):
        tags = {
            "artist": ["Main, Guest"],
            "title": ["Song"],
        }

        self.assertEqual(
            derive_candidates(
                Path("/music/Main - Song (feat. Guest).opus"),
                tags,
                Path("/music"),
            ),
            [("Main", "Song (feat. Guest)")],
        )

    def test_first_artist_fallback_keeps_feature_in_title(self):
        self.assertEqual(
            first_artist_fallbacks(
                [("Main, Guest, Writer", "Song (feat. Guest)")]
            ),
            [("Main", "Song (feat. Guest)")],
        )


class CandidateTierTests(unittest.TestCase):
    @staticmethod
    def args():
        return SimpleNamespace(
            no_fingerprint=False,
            min_score=0.5,
            provider_order=["itunes", "deezer"],
            fallback=True,
            min_similarity=0.6,
        )

    @patch("autotag.from_deezer")
    @patch("autotag.from_itunes")
    def test_all_providers_try_full_credit_before_first_artist(
        self, from_itunes, from_deezer
    ):
        calls = []

        def itunes(artist, title, _limiter, _threshold, album=""):
            calls.append(("itunes", artist, title))
            if artist == "Ayetian":
                return {"artist": "Ayetian", "title": title}
            raise Unidentified("no itunes match")

        def deezer(artist, title, _limiter, _threshold, album=""):
            calls.append(("deezer", artist, title))
            raise Unidentified("no deezer match")

        from_itunes.side_effect = itunes
        from_deezer.side_effect = deezer
        artist = "Ayetian, Guest, Writer, Producer"
        tags = {"artist": [artist], "title": ["Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / f"{artist} - Song.opus"
            song.write_bytes(b"audio")
            result = resolve(
                song,
                root,
                self.args(),
                {
                    "itunes": RateLimiter(0),
                    "deezer": RateLimiter(0),
                },
                "",
                tags,
            )

        self.assertEqual(result["artist"], "Ayetian")
        self.assertEqual(
            calls,
            [
                ("itunes", artist, "Song"),
                ("deezer", artist, "Song"),
                ("itunes", "Ayetian", "Song"),
            ],
        )

    @patch("autotag.from_deezer")
    @patch("autotag.from_itunes", side_effect=Unidentified("no itunes match"))
    def test_exact_later_provider_beats_first_artist_fallback(
        self, from_itunes, from_deezer
    ):
        artist = "Main, Guest, Writer, Producer"
        from_deezer.return_value = {"artist": "Main, Guest", "title": "Song"}
        tags = {"artist": [artist], "title": ["Song"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / f"{artist} - Song.opus"
            song.write_bytes(b"audio")
            result = resolve(
                song,
                root,
                self.args(),
                {
                    "itunes": RateLimiter(0),
                    "deezer": RateLimiter(0),
                },
                "",
                tags,
            )

        self.assertEqual(result["artist"], "Main, Guest")
        from_itunes.assert_called_once()
        from_deezer.assert_called_once()

    @patch("autotag.from_deezer")
    @patch("autotag.from_itunes")
    def test_stronger_later_result_wins_in_first_artist_tier(
        self, from_itunes, from_deezer
    ):
        full_artist = "Ayetian, DJ Mac, Writer, Producer"

        def itunes(artist, _title, _limiter, _threshold, album=""):
            if artist == full_artist:
                raise Unidentified("no itunes match")
            return {"artist": "DJ Mac & Ayetian", "title": "Balance (Mixed)"}

        def deezer(artist, _title, _limiter, _threshold, album=""):
            if artist == full_artist:
                raise Unidentified("no deezer match")
            return {"artist": "Ayetian", "title": "Balance"}

        from_itunes.side_effect = itunes
        from_deezer.side_effect = deezer
        tags = {"artist": [full_artist], "title": ["Balance"]}

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            song = root / f"{full_artist} - Balance.opus"
            song.write_bytes(b"audio")
            result = resolve(
                song,
                root,
                self.args(),
                {
                    "itunes": RateLimiter(0),
                    "deezer": RateLimiter(0),
                },
                "",
                tags,
            )

        self.assertEqual(result, {"artist": "Ayetian", "title": "Balance"})
        self.assertEqual(from_itunes.call_count, 2)
        self.assertEqual(from_deezer.call_count, 2)


class FeatureCreditOutputTests(unittest.TestCase):
    def test_drops_credit_when_final_artist_already_contains_it(self):
        prepared = prepare_metadata(
            {},
            {
                "artist": "Main, Guest",
                "title": "Song (feat. Guest)",
            },
            force=False,
        )

        self.assertEqual(prepared["title"], "Song")

    def test_keeps_credit_when_existing_artist_will_not_be_overwritten(self):
        prepared = prepare_metadata(
            {"artist": ["Main"]},
            {
                "artist": "Main, Guest",
                "title": "Song (feat. Guest)",
            },
            force=False,
        )

        self.assertEqual(prepared["title"], "Song (feat. Guest)")

    def test_unbracketed_duplicate_credit_is_cleaned(self):
        self.assertEqual(
            drop_redundant_feat("Song feat. Guest", "Main, Guest"),
            "Song",
        )

    def test_force_preserves_richer_existing_artist_credit(self):
        prepared = prepare_metadata(
            {
                "artist": ["Didi B, Zlatan, Chley"],
                "title": ["Je m'appelle"],
            },
            {"artist": "Didi B", "title": "Je m'appelle"},
            force=True,
        )

        self.assertEqual(prepared["artist"], "Didi B, Zlatan, Chley")
        self.assertEqual(prepared["_preserved_credits"], "Zlatan, Chley")

    def test_force_recovers_richer_credit_still_present_in_filename(self):
        prepared = prepare_metadata(
            {"artist": ["Didi B"], "title": ["Je m'appelle"]},
            {"artist": "Didi B", "title": "Je m'appelle"},
            force=True,
            path=Path("Didi B, Zlatan, Chley - Je m'appelle.opus"),
        )

        self.assertEqual(prepared["artist"], "Didi B, Zlatan, Chley")
        self.assertEqual(prepared["_preserved_credits"], "Zlatan, Chley")

    def test_force_can_explicitly_allow_narrower_credit(self):
        prepared = prepare_metadata(
            {
                "artist": ["Didi B, Zlatan, Chley"],
                "title": ["Je m'appelle"],
            },
            {"artist": "Didi B", "title": "Je m'appelle"},
            force=True,
            allow_credit_loss=True,
        )

        self.assertEqual(prepared["artist"], "Didi B")
        self.assertNotIn("_preserved_credits", prepared)

    def test_credit_can_move_to_title_without_being_lost(self):
        self.assertEqual(
            missing_credit_names(
                "Main, Guest",
                "Song",
                "Main",
                "Song (feat. Guest)",
            ),
            [],
        )

    def test_credit_comparison_accepts_spelling_and_order_normalization(self):
        self.assertEqual(
            missing_credit_names(
                "Kiff No Beat, Arafat Dj, Mink's",
                "Song",
                "Kiff No Beat",
                "Song (feat. DJ Arafat & Minks)",
            ),
            [],
        )

    def test_credit_comparison_does_not_merge_distinct_prefix_names(self):
        self.assertEqual(
            missing_credit_names(
                "Didi B",
                "Song",
                "Didi",
                "Song",
            ),
            ["Didi B"],
        )

    def test_credit_separator_consumes_feat_period(self):
        self.assertEqual(
            missing_credit_names(
                "Main feat. Guest",
                "Song",
                "Main",
                "Song",
            ),
            ["Guest"],
        )


class YouTubeCreditMetadataTests(unittest.TestCase):
    @patch(
        "autotag.ytdlp_auth_args",
        return_value=["--cookies-from-browser", "firefox"],
    )
    @patch("autotag.shutil.which", return_value="/usr/bin/yt-dlp")
    @patch("autotag.subprocess.run")
    def test_reads_and_deduplicates_structured_artists(
        self,
        run,
        _which,
        _auth_args,
    ):
        run.return_value = SimpleNamespace(
            returncode=0,
            stdout=json.dumps(
                {
                    "artist": "Didi B, Zlatan, Chley",
                    "artists": ["Didi B", "Zlatan", "Chley", "Didi B"],
                    "track": "Je m'appelle",
                }
            ),
            stderr="",
        )

        result = youtube_credit_metadata(
            "https://www.youtube.com/watch?v=video-id"
        )

        self.assertEqual(
            result,
            {
                "artist": "Didi B, Zlatan, Chley",
                "title": "Je m'appelle",
            },
        )
        command = run.call_args.args[0]
        self.assertIn("--ignore-config", command)
        self.assertIn("--no-playlist", command)
        self.assertIn("--cookies-from-browser", command)
        self.assertIn("firefox", command)

    def test_rejects_non_youtube_purl(self):
        with self.assertRaisesRegex(Unidentified, "supported YouTube purl"):
            youtube_credit_metadata("https://example.com/track")


class YouTubeCreditRecoveryTests(unittest.TestCase):
    path = Path("/music/Didi B, Zlatan, Chley - Je m'appelle.opus")
    tags = {
        "artist": ["Didi B"],
        "title": ["Je m'appelle"],
        "purl": ["https://www.youtube.com/watch?v=video-id"],
    }

    def test_filename_signals_missing_artist_credits(self):
        self.assertEqual(
            filename_credit_loss(self.path, self.tags),
            ["Zlatan", "Chley"],
        )

    @patch("autotag.youtube_credit_metadata")
    def test_verifies_purl_and_returns_complete_artist(self, metadata):
        metadata.return_value = {
            "artist": "Didi B, Zlatan, Chley",
            "title": "Je m'appelle",
        }

        self.assertEqual(
            recovered_youtube_artist(self.path, self.tags),
            "Didi B, Zlatan, Chley",
        )

    @patch("autotag.youtube_credit_metadata")
    def test_rejects_mismatched_purl_title(self, metadata):
        metadata.return_value = {
            "artist": "Didi B, Zlatan, Chley",
            "title": "A different song",
        }

        with self.assertRaisesRegex(Unidentified, "title does not match"):
            recovered_youtube_artist(self.path, self.tags)

    @patch("autotag.write_tags")
    @patch(
        "autotag.recovered_youtube_artist",
        return_value="Didi B, Zlatan, Chley",
    )
    @patch("autotag.read_tags")
    def test_dry_run_reports_without_writing(self, read_tags, _recover, write_tags):
        read_tags.return_value = self.tags
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            return_code = restore_youtube_credit_tags(
                [(self.path, Path("/music"))],
                dry_run=True,
            )

        self.assertEqual(return_code, 0)
        self.assertIn("would restore ARTIST", output.getvalue())
        self.assertIn("1 ARTIST tag to restore", output.getvalue())
        write_tags.assert_not_called()

    @patch("autotag.write_tags")
    @patch(
        "autotag.recovered_youtube_artist",
        return_value="Didi B, Zlatan, Chley",
    )
    @patch("autotag.read_tags")
    def test_default_mode_writes_only_artist(self, read_tags, _recover, write_tags):
        read_tags.return_value = self.tags

        return_code = restore_youtube_credit_tags(
            [(self.path, Path("/music"))],
            dry_run=False,
        )

        self.assertEqual(return_code, 0)
        write_tags.assert_called_once_with(
            self.path,
            {"artist": "Didi B, Zlatan, Chley"},
            force=True,
            tags=self.tags,
        )

    @patch("autotag.acoustid_key")
    @patch("autotag.restore_youtube_credit_tags", return_value=0)
    @patch("autotag.collect")
    def test_cli_mode_bypasses_catalog_lookup(
        self,
        collect,
        restore_credit_tags,
        acoustid_key,
    ):
        files = [(self.path, Path("/music"))]
        collect.return_value = files
        with patch.object(
            sys,
            "argv",
            [
                "autotag.py",
                "--restore-youtube-credits",
                "/music",
            ],
        ):
            return_code = autotag.main()

        self.assertEqual(return_code, 0)
        restore_credit_tags.assert_called_once_with(files, False)
        acoustid_key.assert_not_called()

    @patch("autotag.music_library_dir", return_value=Path("/configured/music"))
    @patch("autotag.acoustid_key")
    @patch("autotag.restore_youtube_credit_tags", return_value=0)
    @patch("autotag.collect")
    def test_cli_defaults_to_configured_music_library(
        self,
        collect,
        restore_credit_tags,
        acoustid_key,
        _music_library_dir,
    ):
        files = [(self.path, Path("/configured/music"))]
        collect.return_value = files
        with patch.object(
            sys,
            "argv",
            ["autotag.py", "--restore-youtube-credits"],
        ):
            return_code = autotag.main()

        self.assertEqual(return_code, 0)
        collect.assert_called_once_with(
            ["/configured/music"],
            set(autotag.SUPPORTED),
        )
        restore_credit_tags.assert_called_once_with(files, False)
        acoustid_key.assert_not_called()


class MusicBrainzFeatureTests(unittest.TestCase):
    @patch("autotag.mb_search")
    def test_skips_solo_recording_before_featured_recording(self, mb_search):
        mb_search.return_value = [
            {
                "score": 100,
                "title": "No Lie",
                "artist-credit": [{"artist": {"name": "Sean Paul"}}],
                "releases": [],
            },
            {
                "score": 100,
                "title": "No Lie",
                "artist-credit": [
                    {"artist": {"name": "Sean Paul"}},
                    {"artist": {"name": "Dua Lipa"}},
                ],
                "releases": [],
            },
        ]

        result = from_musicbrainz(
            "Sean Paul",
            "No Lie (feat. Dua Lipa)",
            RateLimiter(0),
        )

        self.assertEqual(result["artist"], "Sean Paul, Dua Lipa")
        self.assertEqual(result["title"], "No Lie")


if __name__ == "__main__":
    unittest.main()
