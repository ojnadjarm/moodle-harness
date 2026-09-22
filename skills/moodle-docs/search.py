#!/usr/bin/env python3
"""BM25 search over the local moodle-devdocs mirror; prints top pages with snippets."""

import argparse
import math
import re
from collections import Counter
from pathlib import Path

ROOT = Path.home() / ".moodle-devdocs"
RELEASE_PREFIXES = ("general/releases", "general/app_releases", "general/_releases")
NOISE_PREFIXES = ("general/community/meetings", "general/community/credits", "general/documentation")
TOKEN_RE = re.compile(r"[a-z0-9_]+")
TITLE_RE = re.compile(r"^---\s*\n.*?^title:\s*(.+?)\s*$.*?^---\s*$", re.S | re.M)
STOPWORDS = {"the", "a", "an", "and", "or", "of", "to", "in", "is", "it", "for", "on",
             "with", "as", "be", "by", "this", "that", "are", "how", "do", "i", "you",
             "can", "use", "using", "moodle"}


def tokens(text):
    out = []
    for tok in TOKEN_RE.findall(text.lower()):
        if tok in STOPWORDS or len(tok) < 2:
            continue
        out.append(tok[:-1] if len(tok) > 3 and tok.endswith("s") else tok)
    return out


def load_corpus(dirs, include_releases=False):
    corpus = []
    for base in dirs:
        for path in sorted(base.rglob("*.md*")):
            if path.name.startswith("_") or path.name == "INDEX.md":
                continue
            rel = str(path.relative_to(ROOT))
            if rel.startswith(NOISE_PREFIXES) or (not include_releases and rel.startswith(RELEASE_PREFIXES)):
                continue
            text = path.read_text(errors="replace")
            match = TITLE_RE.match(text)
            title = match.group(1).strip().strip("'\"") if match else path.stem
            counts = Counter(tokens(text))
            counts.update({t: counts[t] + 3 for t in tokens(title)})
            corpus.append((path, title, text, counts, sum(counts.values())))
    return corpus


def bm25(query, corpus, k1=1.5, b=0.75):
    n = len(corpus)
    avgdl = sum(d[4] for d in corpus) / n
    df = Counter(t for d in corpus for t in set(d[3]) if t in query)
    scores = []
    for path, title, text, counts, dl in corpus:
        score = 0.0
        for term in query:
            tf = counts.get(term, 0)
            if not tf:
                continue
            idf = math.log(1 + (n - df[term] + 0.5) / (df[term] + 0.5))
            score += idf * tf * (k1 + 1) / (tf + k1 * (1 - b + b * dl / avgdl))
        if score > 0:
            scores.append((score, path, title, text))
    return sorted(scores, key=lambda s: -s[0])


def snippets(query, text, limit=2):
    scored = []
    for num, line in enumerate(text.splitlines(), 1):
        hits = sum(1 for t in tokens(line) if t in query)
        if hits and not line.lstrip().startswith(("import ", "---")):
            scored.append((hits, num, line.strip()[:160]))
    scored.sort(key=lambda s: -s[0])
    return sorted(scored[:limit], key=lambda s: s[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", help="search terms, e.g. 'hook listener callback'")
    parser.add_argument("--version", help="search a stable branch snapshot, e.g. 5.1")
    parser.add_argument("--releases", action="store_true",
                        help="include release-note pages in the corpus")
    parser.add_argument("-n", type=int, default=6, help="results to show (default 6)")
    args = parser.parse_args()

    docs = ROOT / f"versioned_docs/version-{args.version}" if args.version else ROOT / "docs"
    if not docs.is_dir():
        raise SystemExit(f"error: {docs} not found — run sync.sh (or check the version)")
    query = set(tokens(args.query))
    results = bm25(query, load_corpus([docs, ROOT / "general"], include_releases=args.releases))

    if not results:
        raise SystemExit("no matches — try different terms or plain grep")
    for score, path, title, text in results[: args.n]:
        print(f"\n== {title}  ({path.relative_to(ROOT)})  [{score:.1f}]")
        for _, num, line in snippets(query, text):
            print(f"   {num}: {line}")


if __name__ == "__main__":
    main()
