"""Tavily web search backend for last30days skill.

Uses Tavily Search API to find recent web content (blogs, docs, news, tutorials).
"""

import re
import sys
from datetime import datetime
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

from . import http

ENDPOINT = "https://api.tavily.com/search"

# Domains to exclude (handled by Reddit/X search)
EXCLUDED_DOMAINS = {
    "reddit.com", "www.reddit.com", "old.reddit.com",
    "twitter.com", "www.twitter.com", "x.com", "www.x.com",
}


def search_web(
    topic: str,
    from_date: str,
    to_date: str,
    api_key: str,
    depth: str = "default",
) -> List[Dict[str, Any]]:
    """Search the web via Tavily API."""
    max_results = {"quick": 8, "default": 15, "deep": 25}.get(depth, 15)
    search_depth = "basic" if depth == "quick" else "advanced"

    payload = {
        "api_key": api_key,
        "query": (
            f"{topic}. Focus on content published between {from_date} and {to_date}. "
            f"Exclude reddit.com, x.com, and twitter.com."
        ),
        "search_depth": search_depth,
        "max_results": max_results,
        "include_answer": False,
        "include_raw_content": False,
        "include_images": False,
    }

    sys.stderr.write(f"[Web] Searching Tavily for: {topic}\n")
    sys.stderr.flush()

    response = http.post(ENDPOINT, json_data=payload, timeout=30)
    return _normalize_results(response)


def _normalize_results(response: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Convert Tavily response to websearch item schema."""
    items: List[Dict[str, Any]] = []
    results = response.get("results", [])
    if not isinstance(results, list):
        return items

    for i, result in enumerate(results):
        if not isinstance(result, dict):
            continue

        url = str(result.get("url", "")).strip()
        if not url:
            continue

        domain = _extract_domain(url)
        if not domain:
            continue
        if domain in EXCLUDED_DOMAINS:
            continue

        title = str(result.get("title", "")).strip()
        snippet = str(result.get("content", result.get("snippet", ""))).strip()
        if not title and not snippet:
            continue

        raw_date = result.get("published_date") or result.get("date")
        date = _parse_date(raw_date)
        date_confidence = "med" if date else "low"

        score = result.get("score", result.get("relevance_score", 0.6))
        try:
            relevance = min(1.0, max(0.0, float(score)))
        except (TypeError, ValueError):
            relevance = 0.6

        items.append({
            "id": f"W{i+1}",
            "title": title[:200],
            "url": url,
            "source_domain": domain,
            "snippet": snippet[:500],
            "date": date,
            "date_confidence": date_confidence,
            "relevance": relevance,
            "why_relevant": "",
        })

    sys.stderr.write(f"[Web] Tavily: {len(items)} results\n")
    sys.stderr.flush()
    return items


def _extract_domain(url: str) -> str:
    try:
        domain = urlparse(url).netloc.lower()
        if domain.startswith("www."):
            domain = domain[4:]
        return domain
    except Exception:
        return ""


def _parse_date(value: Any) -> Optional[str]:
    """Parse date to YYYY-MM-DD when possible."""
    if not value:
        return None

    text = str(value).strip()
    if not text:
        return None

    # ISO-like formats: 2026-03-03 or 2026-03-03T12:34:56Z
    iso = re.search(r"(\d{4}-\d{2}-\d{2})", text)
    if iso:
        return iso.group(1)

    # RFC2822-ish format fallback
    for fmt in ("%a, %d %b %Y %H:%M:%S %Z", "%d %b %Y", "%b %d, %Y"):
        try:
            return datetime.strptime(text, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None
