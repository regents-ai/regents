"""Validated, path-free rollout configuration for Prime Verifiers."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

_PATH_FREE_IDENTIFIER_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._@+-]{0,255}")
_ROLLOUT_CONFIG_FIELDS = {"provider", "model", "hermes_version", "hermes_digest"}


@dataclass(frozen=True)
class RolloutConfig:
    """The validated scalar-only configuration passed to rollout factories."""

    provider: str
    model: str
    hermes_version: str
    hermes_digest: str

    def __post_init__(self) -> None:
        for name in ("provider", "model", "hermes_version"):
            value = getattr(self, name)
            if type(value) is not str or _PATH_FREE_IDENTIFIER_PATTERN.fullmatch(value) is None:
                raise ValueError(f"Prime rollout config {name} must be a path-free identifier")
        if (
            type(self.hermes_digest) is not str
            or len(self.hermes_digest) != 64
            or any(character not in "0123456789abcdef" for character in self.hermes_digest)
        ):
            raise ValueError("Prime rollout config hermes_digest must be a lowercase SHA-256 digest")

    @classmethod
    def from_dict(cls, value: Any) -> "RolloutConfig":
        if type(value) is not dict:
            raise TypeError("Prime rollout config must be an object")
        missing = _ROLLOUT_CONFIG_FIELDS - set(value)
        unknown = set(value) - _ROLLOUT_CONFIG_FIELDS
        if missing:
            raise ValueError(f"Prime rollout config is missing fields: {', '.join(sorted(missing))}")
        if unknown:
            raise ValueError(f"Prime rollout config has unsupported fields: {', '.join(sorted(map(str, unknown)))}")
        return cls(**value)

    def to_dict(self) -> dict[str, str]:
        return {
            "provider": self.provider,
            "model": self.model,
            "hermes_version": self.hermes_version,
            "hermes_digest": self.hermes_digest,
        }


def require_rollout_config(value: Any) -> RolloutConfig:
    """Revalidate a config's current fields and reject unvalidated mappings."""

    if type(value) is not RolloutConfig:
        if type(value) is dict:
            RolloutConfig.from_dict(value)
        raise TypeError("Prime rollout config must be a validated RolloutConfig")
    return RolloutConfig.from_dict(vars(value))


def hermes_rollout_config(
    *,
    hermes_version: str,
    hermes_digest: str,
    provider: str,
    model: str,
) -> RolloutConfig:
    """Build the scalar-only configuration for the one Hermes rollout path."""

    return RolloutConfig(provider, model, hermes_version, hermes_digest)
