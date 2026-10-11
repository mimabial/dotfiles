from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Game:
    key: str
    backend: str
    name: str
    icon: str
    argv: list[str]

