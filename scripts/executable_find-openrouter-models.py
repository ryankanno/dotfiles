#!/usr/bin/env python3
"""Find and rank OpenRouter models by capability.

Queries the public OpenRouter models API and filters by whether a model
is free and which ``supported_parameters`` it advertises.

    # free models that support tool calling
    find-openrouter-models.py --free --tools

    # free models supporting several parameters
    find-openrouter-models.py --free --params tools,structured_outputs

    # all models supporting tools, ranked by OpenRouter's programming
    # usage ranking (see --category)
    find-openrouter-models.py --tools --category programming

    # tool-capable models sorted cheapest-first (price shown per Mtok)
    find-openrouter-models.py --tools --sort price

Ranking: the models API has no global popularity/rank field, and the
default list order is just newest-first (by created date). OpenRouter's
actual rankings are per-category; passing ``--category NAME`` fetches
that category's usage-ranked order and preserves it (rank #1 first).
Without a category, results are sorted by context window, which is NOT a
popularity rank. Tool-calling *quality* and a model's concurrency/worker
limit are not exposed by the API at all.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from typing import Any


MODELS_URL = "https://openrouter.ai/api/v1/models"
_REQUEST_TIMEOUT_S = 30


def is_free(model: dict[str, Any]) -> bool:
    """Return True when the model id ends in ``:free``."""
    return model.get("id", "").endswith(":free")


def has_params(model: dict[str, Any], required: list[str]) -> bool:
    """Return True when the model advertises all ``required`` params."""
    params = set(model.get("supported_parameters") or [])
    return all(p in params for p in required)


def price_per_mtok(model: dict[str, Any]) -> tuple[float, float]:
    """Return (prompt, completion) price in USD per million tokens.

    OpenRouter reports pricing as USD-per-token strings; missing or
    unparseable values are treated as 0 (e.g. free models).
    """
    pricing = model.get("pricing") or {}

    def _mt(key: str) -> float:
        try:
            return float(pricing.get(key) or 0.0) * 1e6
        except (TypeError, ValueError):
            return 0.0

    return _mt("prompt"), _mt("completion")


def select_models(
    models: list[dict[str, Any]],
    *,
    free: bool,
    params: list[str],
) -> list[dict[str, Any]]:
    """Filter models by free-ness and required params, keeping order."""
    out = []
    for model in models:
        if free and not is_free(model):
            continue
        if not has_params(model, params):
            continue
        out.append(model)
    return out


def fetch_models(
    category: str | None = None,
    url: str = MODELS_URL,
) -> list[dict[str, Any]]:
    """Fetch the model list, optionally in a category's ranked order."""
    if category:
        query = urllib.parse.urlencode({"category": category})
        url = f"{url}?{query}"
    with urllib.request.urlopen(url, timeout=_REQUEST_TIMEOUT_S) as response:
        payload = json.load(response)
    return list(payload.get("data", []))


def _print_rows(models: list[dict[str, Any]], *, ranked: bool) -> None:
    for i, model in enumerate(models, start=1):
        ctx = model.get("context_length") or 0
        pin, pout = price_per_mtok(model)
        prefix = f"{i:>3}. " if ranked else "  "
        sys.stdout.write(
            f"{prefix}{model['id']:<52} {ctx:>10,} ctx "
            f"${pin:>7.3f} in ${pout:>7.3f} out /Mtok\n"
        )


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Find and rank OpenRouter models by capability."
    )
    parser.add_argument(
        "--free", action="store_true", help="only ``:free`` models"
    )
    parser.add_argument(
        "--tools",
        action="store_true",
        help="require tool calling (shorthand for --params tools)",
    )
    parser.add_argument(
        "--params",
        default="",
        help="comma-separated supported_parameters all required",
    )
    parser.add_argument(
        "--category",
        default=None,
        help="rank by this OpenRouter category's usage ranking",
    )
    parser.add_argument(
        "--sort",
        choices=("context", "price"),
        default="context",
        help="sort when not using --category (default: context)",
    )
    parser.add_argument(
        "--limit", type=int, default=0, help="show at most N (0 = all)"
    )
    parser.add_argument(
        "--self-test", action="store_true", help="run internal checks"
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Filter and rank OpenRouter models per the CLI options."""
    args = _parse_args(argv)
    if args.self_test:
        return _self_test()

    params = [p.strip() for p in args.params.split(",") if p.strip()]
    if args.tools and "tools" not in params:
        params.append("tools")

    models = fetch_models(category=args.category)
    models = select_models(models, free=args.free, params=params)
    ranked = args.category is not None
    if not ranked:
        if args.sort == "price":
            models.sort(key=lambda m: sum(price_per_mtok(m)))
        else:
            models.sort(
                key=lambda m: m.get("context_length") or 0, reverse=True
            )
    if args.limit > 0:
        models = models[: args.limit]

    if not models:
        sys.stdout.write("No matching models.\n")
        return 0
    if ranked:
        label = "by category rank"
    else:
        label = f"by {args.sort}"
    sys.stdout.write(f"{len(models)} model(s) ({label}):\n")
    _print_rows(models, ranked=ranked)
    return 0


def _self_test() -> int:
    sample: list[dict[str, Any]] = [
        {"id": "a:free", "supported_parameters": ["tools"], "context_length": 5},
        {"id": "b:free", "supported_parameters": ["tools", "x"], "context_length": 9},
        {"id": "c", "supported_parameters": ["tools"], "context_length": 8},
        {"id": "d:free", "supported_parameters": ["x"], "context_length": 1},
    ]
    # free + tools, order preserved
    got = select_models(sample, free=True, params=["tools"])
    assert [m["id"] for m in got] == ["a:free", "b:free"], got
    # multi-param requires all
    got = select_models(sample, free=True, params=["tools", "x"])
    assert [m["id"] for m in got] == ["b:free"], got
    # no free filter includes the paid model
    got = select_models(sample, free=False, params=["tools"])
    assert [m["id"] for m in got] == ["a:free", "b:free", "c"], got
    assert not is_free({"id": "x"})
    # price parsing: USD/token -> USD/Mtok, missing -> 0
    assert price_per_mtok(
        {"pricing": {"prompt": "0.000001", "completion": "0.000002"}}
    ) == (1.0, 2.0)
    assert price_per_mtok({}) == (0.0, 0.0)
    assert price_per_mtok({"pricing": {"prompt": "bad"}}) == (0.0, 0.0)
    print("self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
