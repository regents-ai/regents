"""Truthful failure types for local Uplift report generation."""

from __future__ import annotations


class UpliftInputError(ValueError):
    """The supplied receipt set cannot support a truthful report."""


class UpliftReceiptNotFound(FileNotFoundError):
    """A requested receipt is not present in the local immutable store."""


class UpliftReportCollisionError(RuntimeError):
    """An immutable report or package path already contains different bytes."""


class UpliftReportConflictError(RuntimeError):
    """A receipt set already has a report with different auxiliary inputs."""
