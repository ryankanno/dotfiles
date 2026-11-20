#!/usr/bin/env python3
"""Find and rank OpenRouter models by capability.

Queries the public OpenRouter models API and filters by price, context
window, provider, modality, and which ``supported_parameters`` a model
advertises.

    # free models that support tool calling
    find-openrouter-models.py --free --tools

    # free models supporting several parameters
    find-openrouter-models.py --free --params tools,structured_outputs

    # all models supporting tools, ranked by OpenRouter's programming
    # usage ranking (see --category)
    find-openrouter-models.py --tools --category programming

    # tool-capable models sorted cheapest-first (price shown per Mtok)
    find-openrouter-models.py --tools --sort price

    # under $2/Mtok combined, at least 200k context
    find-openrouter-models.py --max-price 2 --min-context 200000

    # one provider, models that accept images
    find-openrouter-models.py --match anthropic --vision

    # raw JSON for piping
    find-openrouter-models.py --tools --json | jq -r '.[].id'

Ranking: the models API has no global popularity/rank field, and the
default list order is just newest-first (by created date). OpenRouter's
actual rankings are per-category; passing ``--category NAME`` fetches
that category's usage-ranked order and preserves it (rank #1 first).
Without a category, results are sorted by context window, which is NOT a
popularity rank. Tool-calling *quality* and a model's concurrency/worker
limit are not exposed by the API at all.

Alias entries (ids like ``~vendor/model-latest``) redirect to a concrete
model and would otherwise appear alongside their target; they are dropped
unless ``--include-aliases`` is passed.
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


def is_alias(model: dict[str, Any]) -> bool:
    """Return True when the model only redirects to another model."""
    return model.get("alias_target") is not None


def has_params(model: dict[str, Any], required: list[str]) -> bool:
    """Return True when the model advertises all ``required`` params."""
    params = set(model.get("supported_parameters") or [])
    return all(p in params for p in required)


def has_modalities(model: dict[str, Any], required: list[str]) -> bool:
    """Return True when the model accepts all ``required`` input modalities."""
    architecture = model.get("architecture") or {}
    accepted = set(architecture.get("input_modalities") or [])
    return all(m in accepted for m in required)


def matches_text(model: dict[str, Any], needle: str) -> bool:
    """Return True when ``needle`` appears in the model's id or name.

    Case-insensitive; an empty needle matches everything.
    """
    if not needle:
        return True
    needle = needle.lower()
    haystack = f"{model.get('id', '')} {model.get('name', '')}".lower()
    return needle in haystack


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


def has_known_price(model: dict[str, Any]) -> bool:
    """Return False when OpenRouter reports pricing it cannot commit to.

    Router models (``openrouter/auto`` and friends) choose a downstream
    model per request and report ``-1`` for every price field.
    """
    return all(price >= 0 for price in price_per_mtok(model))


def total_price_per_mtok(model: dict[str, Any]) -> float:
    """Return prompt + completion price in USD per million tokens."""
    return sum(price_per_mtok(model))


def select_models(
    models: list[dict[str, Any]],
    *,
    free: bool = False,
    params: list[str] | None = None,
    max_price: float | None = None,
    min_context: int = 0,
    match: str = "",
    modalities: list[str] | None = None,
    include_aliases: bool = False,
) -> list[dict[str, Any]]:
    """Filter models by every supplied criterion, keeping order.

    ``max_price`` caps prompt + completion combined, matching what
    ``--sort price`` orders by.
    """
    out = []
    for model in models:
        if not include_aliases and is_alias(model):
            continue
        if free and not is_free(model):
            continue
        if not has_params(model, params or []):
            continue
        if not has_modalities(model, modalities or []):
            continue
        if not matches_text(model, match):
            continue
        if max_price is not None and (
            not has_known_price(model)
            or total_price_per_mtok(model) > max_price
        ):
            continue
        if (model.get("context_length") or 0) < min_context:
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
        price = (
            f"${pin:>7.3f} in ${pout:>7.3f} out /Mtok"
            if has_known_price(model)
            else "variable pricing (router)"
        )
        sys.stdout.write(f"{prefix}{model['id']:<52} {ctx:>10,} ctx {price}\n")


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
        "--max-price",
        type=float,
        default=None,
        help="cap USD/Mtok for prompt + completion combined",
    )
    parser.add_argument(
        "--min-context",
        type=int,
        default=0,
        help="require at least this many context tokens",
    )
    parser.add_argument(
        "--match",
        default="",
        help="substring of the model id or name (case-insensitive)",
    )
    parser.add_argument(
        "--modality",
        default="",
        help="comma-separated input modalities all required (e.g. image)",
    )
    parser.add_argument(
        "--vision",
        action="store_true",
        help="require image input (shorthand for --modality image)",
    )
    parser.add_argument(
        "--include-aliases",
        action="store_true",
        help="keep ``~vendor/model-latest`` redirect entries",
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
        "--json", action="store_true", help="emit raw JSON instead of a table"
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

    modalities = [m.strip() for m in args.modality.split(",") if m.strip()]
    if args.vision and "image" not in modalities:
        modalities.append("image")

    models = fetch_models(category=args.category)
    models = select_models(
        models,
        free=args.free,
        params=params,
        max_price=args.max_price,
        min_context=args.min_context,
        match=args.match,
        modalities=modalities,
        include_aliases=args.include_aliases,
    )
    ranked = args.category is not None
    if not ranked:
        if args.sort == "price":
            # Router models report -1, which would otherwise sort as the
            # cheapest thing on offer; park them at the end instead.
            models.sort(
                key=lambda m: (not has_known_price(m), total_price_per_mtok(m))
            )
        else:
            models.sort(
                key=lambda m: m.get("context_length") or 0, reverse=True
            )
    if args.limit > 0:
        models = models[: args.limit]

    if args.json:
        json.dump(models, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

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
    assert total_price_per_mtok(
        {"pricing": {"prompt": "0.000001", "completion": "0.000002"}}
    ) == 3.0

    priced: list[dict[str, Any]] = [
        {
            "id": "cheap",
            "context_length": 1000,
            "pricing": {"prompt": "0.000001", "completion": "0.000001"},
        },
        {
            "id": "dear",
            "context_length": 500000,
            "pricing": {"prompt": "0.00001", "completion": "0.00001"},
        },
    ]
    # max_price caps prompt + completion combined, so cheap (2.0) survives
    # a cap of 2 and dear (20.0) does not
    got = select_models(priced, max_price=2.0)
    assert [m["id"] for m in got] == ["cheap"], got
    # a cap just under the exact total drops it, so the bound is real
    assert select_models(priced, max_price=1.99) == []
    # router models report -1 per field; they must not read as free, and a
    # price cap must exclude them rather than rank them cheapest
    router: list[dict[str, Any]] = [
        {"id": "openrouter/auto", "pricing": {"prompt": "-1", "completion": "-1"}}
    ]
    assert not has_known_price(router[0])
    assert has_known_price(priced[0])
    assert select_models(router, max_price=1000.0) == []
    # with no cap asked for, they are still listed
    assert len(select_models(router)) == 1
    # min_context is a floor, also inclusive
    got = select_models(priced, min_context=1000)
    assert [m["id"] for m in got] == ["cheap", "dear"], got
    got = select_models(priced, min_context=1001)
    assert [m["id"] for m in got] == ["dear"], got

    named: list[dict[str, Any]] = [
        {"id": "anthropic/claude", "name": "Anthropic: Claude"},
        {"id": "qwen/qwen3", "name": "Qwen3"},
    ]
    # match is case-insensitive and spans id and name
    assert [m["id"] for m in select_models(named, match="ANTHROPIC")] == [
        "anthropic/claude"
    ]
    assert [m["id"] for m in select_models(named, match="qwen3")] == ["qwen/qwen3"]
    # an empty needle matches everything
    assert len(select_models(named, match="")) == 2

    modal: list[dict[str, Any]] = [
        {"id": "text", "architecture": {"input_modalities": ["text"]}},
        {"id": "vision", "architecture": {"input_modalities": ["text", "image"]}},
        {"id": "bare"},
    ]
    got = select_models(modal, modalities=["image"])
    assert [m["id"] for m in got] == ["vision"], got
    # a model with no architecture block matches only an empty requirement
    assert len(select_models(modal, modalities=[])) == 3

    aliased: list[dict[str, Any]] = [
        {"id": "~v/latest", "alias_target": {"slug": "v/real"}},
        {"id": "v/real"},
    ]
    # aliases are dropped by default, restored on request
    assert [m["id"] for m in select_models(aliased)] == ["v/real"]
    assert len(select_models(aliased, include_aliases=True)) == 2

    print("self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
