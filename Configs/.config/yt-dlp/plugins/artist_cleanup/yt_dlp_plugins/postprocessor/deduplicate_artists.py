from yt_dlp.postprocessor.common import PostProcessor

__all__ = ["DeduplicateArtistsPP"]


class DeduplicateArtistsPP(PostProcessor):
    CREDIT_FIELDS = (
        ("artists", "artist"),
        ("creators", "creator"),
        ("album_artists", "album_artist"),
        ("composers", "composer"),
    )

    @staticmethod
    def _deduplicate(information: dict, plural: str, singular: str) -> None:
        values = information.get(plural)
        if not isinstance(values, (list, tuple)):
            return

        unique = []
        seen = set()
        for value in values:
            if not isinstance(value, str):
                continue
            value = " ".join(value.split())
            key = value.casefold()
            if not value or key in seen:
                continue
            seen.add(key)
            unique.append(value)

        if len(unique) == len(values):
            return
        information[plural] = unique
        information[singular] = ", ".join(unique)

    def run(self, information):
        for plural, singular in self.CREDIT_FIELDS:
            self._deduplicate(information, plural, singular)
        return [], information
