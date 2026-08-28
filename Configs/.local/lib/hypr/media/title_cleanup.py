"""Shared cleanup for display and tag titles sourced from video sites."""

import re


# "vidéo"/"vídeo" appear as often as "video" on francophone and lusophone uploads.
_VIDEO = r"v[ií]d[eé]o"
_NOISE_TAG = (
    rf"(?:official\s+)?(?:music\s+|lyrics?\s+|audio\s+|performance\s+)?{_VIDEO}"
    r"(?:\s+(?:hd|hq|4k|8k))?"
    rf"|{_VIDEO}\s+clip"
    r"|(?:official\s+)?lyrics?\s+visuali[sz]er"
    rf"|official\s+(?:audio|visuali[sz]er|performance\s+{_VIDEO})"
    rf"|{_VIDEO}\s+(?:oficial|officielle?)"
    r"|clip\s+officiel(?:le)?|(?:official\s+)?(?:audio\s+only|full\s+stream)"
    rf"|(?:\w+\s+)?{_VIDEO}"
    r"|prod(?:uced)?\.?\s+by\s+[^)\]】）｝]*"
    r"|lyrics?|audio|visuali[sz]er|mv|hd|hq|4k|8k"
    r"|remaster(?:ed)?(?:\s+\d{4})?"
    r"|explicit|clean|official"
)
_NOISE_YEAR = r"(?:\s+\d{4})?"
_OPEN, _CLOSE = r"[\(\[【（｛]", r"[\)\]】）｝]"
_NOISE_CREDIT = r"(?:\s*by\s+[^)\]】）｝]*)?"

NOISE_BRACKET = re.compile(
    rf"\s*{_OPEN}\s*(?:{_NOISE_TAG}){_NOISE_YEAR}{_NOISE_CREDIT}\s*{_CLOSE}{_NOISE_YEAR}",
    re.I,
)

# A bare unbracketed keyword may be a real title, so require video boilerplate.
_NOISE_TAG_QUALIFIED = (
    r"(?:official(?:\s+(?:music|lyrics?))?|music|lyrics?|performance)\s+v[ií]d[eé]o"
    r"|v[ií]d[eé]o\s+(?:officielle?|oficial|clip|lyrics?)"
    r"|clip\s+officiel(?:le)?"
    r"|official\s+(?:audio|visuali[sz]er)"
    r"|(?:official\s+)?(?:audio\s+only|full\s+stream)"
)
NOISE_TRAILING = re.compile(
    rf"\s*[|｜:-]\s*(?:{_NOISE_TAG_QUALIFIED}){_NOISE_YEAR}(?=\s*$|\s*{_OPEN})",
    re.I,
)
WEB_BRAND_SUFFIX = re.compile(r"\s*[-–—|]\s*YouTube(?:\s+Music)?\s*$", re.I)


def clean_title(title: str) -> str:
    cleaned = title.replace("⧸", "/")
    cleaned = NOISE_BRACKET.sub("", cleaned)
    cleaned = NOISE_TRAILING.sub("", cleaned)
    cleaned = re.sub(r"\s*-\s*Topic\s*$", "", cleaned, flags=re.I)
    return re.sub(r"\s{2,}", " ", cleaned).strip(" -–—")


def clean_web_title(title: str) -> str:
    """Clean upload annotations plus a browser site's document-title branding."""
    return WEB_BRAND_SUFFIX.sub("", clean_title(title)).strip(" -–—")
