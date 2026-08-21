#!/usr/bin/env python3
"""Canonicalize a collector reading on stdin so two implementations can be
diffed for real divergence rather than for incidental formatting."""
import json
import re
import sys


def scrub_detail(text: str) -> str:
    """Embedded RPC error payloads are rendered by each language: Python uses
    dict repr, Swift uses JSON. Same content, different syntax — strip quotes
    and spaces inside braces so the content is still compared and the syntax
    is not."""
    return re.sub(r"\{.*\}", lambda m: re.sub(r"['\" ]", "", m.group(0)), text)


def scrub(provider: dict) -> dict:
    # reset_at moves between the two runs and percentages drift as quota is
    # spent; both are compared for presence and shape, not exact value.
    for meter in provider.get("meters", []):
        if meter.get("reset_at"):
            meter["reset_at"] = "<timestamp>"
        if meter.get("percent") is not None:
            meter["percent"] = round(float(meter["percent"]), 0)
    provider["details"] = [scrub_detail(d) for d in provider.get("details", [])]
    return provider


providers = [scrub(p) for p in json.load(sys.stdin)]
print(json.dumps(providers, indent=2, sort_keys=True))
