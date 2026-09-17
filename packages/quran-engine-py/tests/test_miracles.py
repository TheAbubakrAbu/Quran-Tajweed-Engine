"""The scientific-miracles corpus: 202 articles under 15 categories.

A deliberate translation of packages/quran-engine-js/test/miracles.test.js: the same corpus, the
same counts, the same shape checks, so a port that drifts fails here rather than in a consumer.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from quran_engine import Engine  # noqa: E402
from quran_engine.miracles import MIRACLE_LEVELS, Miracles  # noqa: E402

engine = Engine.load()
m = engine.miracles


def test_counts():
    c = m.count()
    assert c["articles"] == 202, c
    assert c["categories"] == 15, c
    assert c["ayahRefs"] == 278, c
    assert len(m.all()) == 202
    assert len(m.categories()) == 15


def test_slug_round_trips():
    article = m.by_slug("big_bang_crunch")
    assert article is not None
    assert article["title"] == "Big Bang"
    assert article["category"] == "cosmology"
    assert article["level"] == "extreme"
    assert m.by_slug("no_such_article") is None
    # Every slug is unique, which is what makes the lookup a round-trip and not a first-match.
    assert len({a["slug"] for a in m.all()}) == 202


def test_categories_partition():
    total = 0
    for category in m.categories():
        members = m.by_category(category["id"])
        assert members, category["id"]
        total += len(members)
    assert total == 202, total
    assert len(m.by_category("cosmology")) == 18
    assert m.by_category("no_such_category") == []


def test_category_lookup():
    cosmology = m.category("cosmology")
    assert cosmology is not None
    assert cosmology["id"] == "cosmology"
    assert cosmology["level"] == "advanced"
    assert m.category("no_such_category") is None


def test_article_level_is_its_own():
    # Big Bang is filed under cosmology, which the corpus rates "advanced", while the article
    # itself is "extreme". Filtering on the category's level would put it in the wrong bucket, and
    # it is not one article out of place: most of the corpus disagrees with its category.
    assert m.category("cosmology")["level"] == "advanced"
    assert m.by_slug("big_bang_crunch")["level"] == "extreme"
    cat_level = {c["id"]: c["level"] for c in m.categories()}
    differing = [a for a in m.all() if a["level"] != cat_level[a["category"]]]
    assert len(differing) == 147, len(differing)


def test_levels_run_simple_to_extreme():
    assert m.levels() == ["simple", "intermediate", "advanced", "extreme"]
    assert m.levels() == MIRACLE_LEVELS
    # Sorted as strings, "extreme" would come second. That is the whole reason the rank is
    # hard-coded.
    assert m.levels() != sorted(m.levels())
    assert len(m.by_level("simple")) == 6
    assert len(m.by_level("intermediate")) == 103
    assert len(m.by_level("advanced")) == 37
    assert len(m.by_level("extreme")) == 56
    assert sum(len(m.by_level(level)) for level in MIRACLE_LEVELS) == len(m.all())


def test_every_article_names_known_category_and_level():
    ids = {c["id"] for c in m.categories()}
    for article in m.all():
        assert article["slug"]
        assert article["title"], article["slug"]
        assert article["category"] in ids, article["slug"]
        assert article["level"] in MIRACLE_LEVELS, article["slug"]
        assert article["blocks"], article["slug"]


def test_citing_finds_the_articles_that_reach_an_ayah():
    # 21:30 is cited by exactly two: Big Bang and Exoplanets.
    assert [a["slug"] for a in m.citing(21, 30)] == ["big_bang_crunch", "exoplanets"]
    # 23:14, the embryology verse, by three.
    assert [a["slug"] for a in m.citing(23, 14)] == ["bones", "fetal_development", "human_embryo"]
    assert m.citing(21, 999) == []
    assert m.citing(999, 1) == []


def test_ayah_block_is_a_range():
    # Abjad Numerals cites 111:1-5 as one block. Every ayah in the range reaches it, and 111:6,
    # one past the end, does not (Surah al-Masad has five ayahs, so this also checks the range end
    # is what bounds the search, not the surah).
    assert m.ayah_refs("abjad_numerals") == [{"surah": 111, "ayah": 1, "endAyah": 5}]
    for ayah in (1, 2, 3, 4, 5):
        assert any(a["slug"] == "abjad_numerals" for a in m.citing(111, ayah)), ayah
    assert not any(a["slug"] == "abjad_numerals" for a in m.citing(111, 6))
    assert m.ayah_refs("no_such_article") == []


def test_every_ayah_ref_is_a_real_ayah():
    refs = ranges = 0
    for article in m.all():
        for ref in m.ayah_refs(article["slug"]):
            assert ref["endAyah"] >= ref["ayah"], (article["slug"], ref)
            # Both ends resolve, which is the point of storing the reference rather than the text.
            assert engine.quran.ayah(ref["surah"], ref["ayah"]) is not None, (article["slug"], ref)
            assert engine.quran.ayah(ref["surah"], ref["endAyah"]) is not None, (article["slug"], ref)
            refs += 1
            if ref["endAyah"] > ref["ayah"]:
                ranges += 1
    assert refs == 278, refs
    assert ranges == 49, ranges


def test_no_image_blocks():
    # The site's illustrations are deliberately not republished. A consumer that leaves a gap for
    # a picture would wait forever, so the corpus states it and the blocks bear it out.
    assert m.images_included is False
    kinds = {b["kind"] for a in m.all() for b in a["blocks"]}
    assert "image" not in kinds
    assert sorted(kinds) == ["ayah", "claim", "closer", "lead", "quote", "text"]
    assert "miracles-of-quran.com" in m.source()


def test_links_are_url_or_slug_never_both():
    urls = slugs = 0
    known = {a["slug"] for a in m.all()}
    for article in m.all():
        for block in article["blocks"]:
            for link in block.get("links", []):
                assert link["label"], article["slug"]
                assert ("url" in link) != ("slug" in link), (article["slug"], link)
                if "url" in link:
                    urls += 1
                else:
                    # An internal cross-reference resolves, so following one is `by_slug` and
                    # nothing more.
                    assert link["slug"] in known, (article["slug"], link)
                    assert m.by_slug(link["slug"]) is not None
                    slugs += 1
    assert urls == 73, urls
    assert slugs == 12, slugs
    # One of each form, named, so a port that models only one of them fails here.
    internal = [l for b in m.by_slug("big_bang_crunch")["blocks"] for l in b.get("links", [])]
    assert internal == [{"label": "Dark Energy", "slug": "dark_energy"}]
    external = [l for b in m.by_slug("atoms")["blocks"] for l in b.get("links", []) if "url" in l]
    assert external
    assert all(l["url"].startswith("http") for l in external)


def test_text_leaves_the_quotes_out():
    abjad = m.by_slug("abjad_numerals")
    quote = next(b for b in abjad["blocks"] if b["kind"] == "quote")
    assert quote["sourceLabel"] == "Wikipedia, Abjad Numerals, 2021"
    text = m.text("abjad_numerals")
    # The quote sits between the lead and the first text block, and none of it comes through: it
    # is somebody else's words next to a source label, not the article's voice.
    assert quote["text"][:40] not in text
    assert "Wikipedia" not in text
    # What does come through is claim, lead, text and closer, in reading order.
    assert text.startswith("Alphanumeric code.")
    assert "We found this ancient numeral system encoded in the Quran." in text
    assert len(text.split("\n\n")) == 6
    assert len(m.text("big_bang_crunch").split("\n\n")) == 4
    assert m.text("no_such_article") == ""


def test_search_matches_title_or_prose():
    hits = m.search("big bang")
    assert any(a["slug"] == "big_bang_crunch" for a in hits)
    assert [a["slug"] for a in m.search("BIG BANG")] == [a["slug"] for a in hits]
    assert len(m.search("cosmology", 3)) <= 3
    assert m.search("") == []
    assert m.search("   ") == []
    assert m.search("zzzznotaword") == []


def test_empty_corpus_answers_nothing():
    # ``Engine`` builds this module empty when the file is absent, and every call has to survive
    # that: a consumer without the pack sees an empty corpus, not a crash.
    empty = Miracles()
    assert empty.is_loaded is False
    assert empty.all() == []
    assert empty.categories() == []
    assert empty.by_slug("big_bang_crunch") is None
    assert empty.category("cosmology") is None
    assert empty.levels() == []
    assert empty.citing(21, 30) == []
    assert empty.ayah_refs("big_bang_crunch") == []
    assert empty.text("big_bang_crunch") == ""
    assert empty.search("big bang") == []
    assert empty.count() == {"articles": 0, "categories": 0, "ayahRefs": 0}
    assert m.is_loaded


if __name__ == "__main__":
    passed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print(f"  ok  {name}")
            passed += 1
    print(f"\n{passed} tests passed")
