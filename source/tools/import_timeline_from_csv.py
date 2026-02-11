#!/usr/bin/env python3
"""
Import timeline events into an IRIS case from a CSV file using the REST API.

This script is a thin wrapper around the existing
`/case/timeline/events/csv_upload` endpoint implemented in
`app/blueprints/rest/case/case_timeline_routes.py`.

Expected CSV header (one row per event), as enforced by the server:

    event_date,event_tz,event_title,event_category,event_content,
    event_raw,event_source,event_assets,event_iocs,event_tags

Key mappings:
  - event_date / event_tz: combined into an ISO timestamp and parsed via
    `parse_bf_date_format` and `EventSchema.validate_date` on the server.
  - event_assets: semicolon-separated asset names; each must already exist in
    the case and is resolved to asset IDs.
  - event_iocs: pipe-separated IOC values; each must already exist in the
    case and is resolved to IOC IDs.
  - event_category: category name; resolved to a category ID, or falls back
    to the default category.
  - event_tags: pipe-separated tags, converted server‑side to a comma list.

Authentication:
  - The script is agnostic to auth mechanism; it simply allows you to pass
    either a static bearer token or a `Cookie:` header value.
"""

import argparse
import pathlib
import sys
from typing import Dict, Optional

import requests


def build_headers(api_token: Optional[str], cookie: Optional[str]) -> Dict[str, str]:
    headers: Dict[str, str] = {"Content-Type": "application/json"}

    if api_token:
        # Adjust this header name to your IRIS deployment (e.g. Authorization: Bearer ...)
        headers["Authorization"] = f"Bearer {api_token}"

    if cookie:
        headers["Cookie"] = cookie

    return headers


def import_csv(
    base_url: str,
    case_id: int,
    csv_path: pathlib.Path,
    api_token: Optional[str],
    cookie: Optional[str],
    event_source: str,
    event_in_summary: bool,
    event_in_graph: bool,
    sync_iocs_assets: bool,
) -> int:
    csv_text = csv_path.read_text(encoding="utf-8")

    url = f"{base_url.rstrip('/')}/case/evidences/{case_id}/../timeline/events/csv_upload"
    # The case identifier is provided via the standard access controls that
    # IRIS uses (`ac_requires_case_identifier`), so base_url should already
    # point at the REST root (e.g. https://iris.local/api/v1).

    payload = {
        "CSVData": csv_text,
        "CSVOptions": {
            "event_sync_iocs_assets": sync_iocs_assets,
            "event_in_summary": event_in_summary,
            "event_in_graph": event_in_graph,
            "event_source": event_source,
        },
    }

    headers = build_headers(api_token=api_token, cookie=cookie)

    resp = requests.post(url, json=payload, headers=headers, timeout=60)

    try:
        data = resp.json()
    except ValueError:
        data = {"raw": resp.text}

    if resp.ok:
        print(f"[+] Import succeeded: {data.get('message', '') or data}")
        return 0

    print(f"[-] Import failed (HTTP {resp.status_code}): {data}", file=sys.stderr)
    return 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Import IRIS timeline events from a CSV file via REST API."
    )
    parser.add_argument(
        "--base-url",
        required=True,
        help="Base REST URL, e.g. https://iris.local/api/v1",
    )
    parser.add_argument(
        "--case-id",
        type=int,
        required=True,
        help="IRIS case identifier to import events into.",
    )
    parser.add_argument(
        "--csv",
        required=True,
        help="Path to the CSV file to import.",
    )
    parser.add_argument(
        "--api-token",
        help="Optional bearer token for Authorization header.",
    )
    parser.add_argument(
        "--cookie",
        help="Optional Cookie header value if you want to re‑use an existing session.",
    )
    parser.add_argument(
        "--event-source",
        default="E01 timeline",
        help="Source label to set on imported events (default: 'E01 timeline').",
    )
    parser.add_argument(
        "--no-summary",
        action="store_true",
        help="Do not include imported events in the case summary view.",
    )
    parser.add_argument(
        "--no-graph",
        action="store_true",
        help="Do not include imported events in the timeline visualization graph.",
    )
    parser.add_argument(
        "--sync-iocs-assets",
        action="store_true",
        help="Enable event_sync_iocs_assets in CSVOptions.",
    )

    args = parser.parse_args(argv)

    csv_path = pathlib.Path(args.csv).expanduser().resolve()
    if not csv_path.is_file():
        print(f"CSV file not found: {csv_path}", file=sys.stderr)
        return 1

    return import_csv(
        base_url=args.base_url,
        case_id=args.case_id,
        csv_path=csv_path,
        api_token=args.api_token,
        cookie=args.cookie,
        event_source=args.event_source,
        event_in_summary=not args.no_summary,
        event_in_graph=not args.no_graph,
        sync_iocs_assets=args.sync_iocs_assets,
    )


if __name__ == "__main__":
    raise SystemExit(main())

