# Regenerates legacy.apkg and modern.apkg with the official Anki library:
#   python3 -m venv .venv && .venv/bin/pip install anki && .venv/bin/python make-apkg.py .

import sys, os, tempfile, base64
from anki.collection import Collection, ExportAnkiPackageOptions
from anki.decks import DeckId
out = sys.argv[1]
d = tempfile.mkdtemp()
col = Collection(os.path.join(d, "c.anki2"))
png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGP4z8DAwMDAxMDAwMDAAAANHQEDasKb6QAAAABJRU5ErkJggg==")
open(os.path.join(col.media.dir(), "dog.png"), "wb").write(png)
open(os.path.join(col.media.dir(), "dog.mp3"), "wb").write(b"ID3")
did = col.decks.id("English::Animals")
basic = col.models.by_name("Basic")
n = col.new_note(basic); n["Front"] = "the <b>dog</b>&nbsp;[sound:dog.mp3]"; n["Back"] = 'el perro<br><img src="dog.png">'
col.add_note(n, DeckId(did))
n = col.new_note(basic); n["Front"] = "to get along"; n["Back"] = "llevarse bien"
col.add_note(n, DeckId(did))
cloze = col.models.by_name("Cloze")
n = col.new_note(cloze); n["Text"] = "I {{c1::ran::correr}} home"; n["Back Extra"] = "past of run"
col.add_note(n, DeckId(did))
deck = col.decks.id("English::Animals")
for legacy in (True, False):
    col.export_anki_package(out_path=os.path.join(out, "legacy.apkg" if legacy else "modern.apkg"),
        options=ExportAnkiPackageOptions(with_scheduling=False, with_deck_configs=False, with_media=True, legacy=legacy), limit=None)
col.close()
