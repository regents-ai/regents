"""Local receipt-only Uplift comparison and reporting."""

from .compare import ComparisonData, compare_receipts, decision_sentence
from .errors import UpliftInputError, UpliftReceiptNotFound, UpliftReportCollisionError, UpliftReportConflictError
from .package import assemble_reproduction_package
from .report import generate_uplift_report
from .store import emit_reproduction_package, emit_uplift_result, show_reproduction_package, show_uplift_report

__all__ = [
    "ComparisonData",
    "UpliftInputError",
    "UpliftReceiptNotFound",
    "UpliftReportCollisionError",
    "UpliftReportConflictError",
    "assemble_reproduction_package",
    "compare_receipts",
    "decision_sentence",
    "emit_reproduction_package",
    "emit_uplift_result",
    "generate_uplift_report",
    "show_reproduction_package",
    "show_uplift_report",
]
