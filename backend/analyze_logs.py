#!/usr/bin/env python3
"""
Log Analyzer - Utility to analyze backend request/response logs
"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict

LOGS_DIR = Path("logs")


def analyze_requests():
    """Analyze all requests and show statistics."""
    requests_file = LOGS_DIR / "requests.jsonl"
    
    if not requests_file.exists():
        print("No requests log found.")
        return
    
    requests = []
    with open(requests_file) as f:
        for line in f:
            try:
                requests.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    
    if not requests:
        print("No requests found.")
        return
    
    print(f"\n{'='*80}")
    print(f"REQUESTS ANALYSIS ({len(requests)} total)")
    print(f"{'='*80}\n")
    
    # Group by endpoint
    endpoints = defaultdict(list)
    for req in requests:
        path = req.get("path", "unknown")
        endpoints[path].append(req)
    
    print(f"{'Endpoint':<40} {'Count':<10} {'Methods'}")
    print("-" * 80)
    for endpoint, reqs in sorted(endpoints.items()):
        methods = set(r.get("method") for r in reqs)
        print(f"{endpoint:<40} {len(reqs):<10} {', '.join(sorted(methods))}")
    
    # Show latest requests
    print(f"\n{'Last 5 Requests:':^80}\n")
    for req in requests[-5:]:
        print(f"  {req.get('timestamp')} | {req.get('method')} {req.get('path')}")
        if req.get('body'):
            body_str = json.dumps(req.get('body'), indent=2)
            if len(body_str) > 200:
                body_str = body_str[:200] + "..."
            print(f"    Body: {body_str}")
        print()


def analyze_responses():
    """Analyze all responses and show statistics."""
    responses_file = LOGS_DIR / "responses.jsonl"
    
    if not responses_file.exists():
        print("No responses log found.")
        return
    
    responses = []
    with open(responses_file) as f:
        for line in f:
            try:
                responses.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    
    if not responses:
        print("No responses found.")
        return
    
    print(f"\n{'='*80}")
    print(f"RESPONSES ANALYSIS ({len(responses)} total)")
    print(f"{'='*80}\n")
    
    # Group by status code
    status_codes = defaultdict(list)
    for resp in responses:
        status = resp.get("status_code", "unknown")
        status_codes[status].append(resp)
    
    print(f"{'Status Code':<15} {'Count':<10} {'Avg Time (ms)':<15} {'Avg Size (bytes)'}")
    print("-" * 80)
    for status in sorted(status_codes.keys()):
        resps = status_codes[status]
        avg_time = sum(r.get("response_time_ms", 0) for r in resps) / len(resps)
        avg_size = sum(r.get("response_size_bytes", 0) for r in resps) / len(resps)
        print(f"{str(status):<15} {len(resps):<10} {avg_time:<15.2f} {avg_size:.0f}")
    
    # Show slowest responses
    print(f"\n{'Top 5 Slowest Responses:':^80}\n")
    sorted_responses = sorted(responses, key=lambda x: x.get("response_time_ms", 0), reverse=True)
    for resp in sorted_responses[:5]:
        print(f"  {resp.get('method')} {resp.get('path')} | Status: {resp.get('status_code')} | Time: {resp.get('response_time_ms')}ms | Size: {resp.get('response_size_bytes')} bytes")
    
    # Show fastest responses
    print(f"\n{'Top 5 Fastest Responses:':^80}\n")
    sorted_responses = sorted(responses, key=lambda x: x.get("response_time_ms", 0))
    for resp in sorted_responses[:5]:
        print(f"  {resp.get('method')} {resp.get('path')} | Status: {resp.get('status_code')} | Time: {resp.get('response_time_ms')}ms | Size: {resp.get('response_size_bytes')} bytes")


def analyze_errors():
    """Analyze all errors and show statistics."""
    errors_file = LOGS_DIR / "errors.jsonl"
    
    if not errors_file.exists():
        print("No errors log found.")
        return
    
    errors = []
    with open(errors_file) as f:
        for line in f:
            try:
                errors.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    
    if not errors:
        print("No errors found.")
        return
    
    print(f"\n{'='*80}")
    print(f"ERRORS ANALYSIS ({len(errors)} total)")
    print(f"{'='*80}\n")
    
    # Group by error type
    error_types = defaultdict(list)
    for err in errors:
        error_type = err.get("error_type", "unknown")
        error_types[error_type].append(err)
    
    print(f"{'Error Type':<30} {'Count':<10}")
    print("-" * 80)
    for error_type in sorted(error_types.keys()):
        errs = error_types[error_type]
        print(f"{error_type:<30} {len(errs):<10}")
    
    # Show recent errors
    print(f"\n{'Recent Errors:':^80}\n")
    for err in errors[-10:]:
        print(f"  {err.get('timestamp')} | {err.get('method')} {err.get('path')}")
        print(f"    Error: {err.get('error_message')}")
        print()


def show_request_response_pair(request_id: str):
    """Show a specific request and its response."""
    requests_file = LOGS_DIR / "requests.jsonl"
    responses_file = LOGS_DIR / "responses.jsonl"
    
    request = None
    response = None
    
    if requests_file.exists():
        with open(requests_file) as f:
            for line in f:
                try:
                    req = json.loads(line)
                    if req.get("request_id") == request_id:
                        request = req
                        break
                except json.JSONDecodeError:
                    continue
    
    if responses_file.exists():
        with open(responses_file) as f:
            for line in f:
                try:
                    resp = json.loads(line)
                    if resp.get("request_id") == request_id:
                        response = resp
                        break
                except json.JSONDecodeError:
                    continue
    
    print(f"\n{'='*80}")
    print(f"REQUEST-RESPONSE PAIR: {request_id}")
    print(f"{'='*80}\n")
    
    if request:
        print("REQUEST:")
        print(json.dumps(request, indent=2))
    else:
        print("REQUEST: Not found")
    
    if response:
        print("\nRESPONSE:")
        print(json.dumps(response, indent=2))
    else:
        print("\nRESPONSE: Not found")


def main():
    if not LOGS_DIR.exists():
        print(f"Logs directory not found: {LOGS_DIR}")
        return
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "--pair" and len(sys.argv) > 2:
            show_request_response_pair(sys.argv[2])
        else:
            print(f"Usage: {sys.argv[0]} [--pair REQUEST_ID]")
    else:
        analyze_requests()
        analyze_responses()
        analyze_errors()
        print(f"\n{'='*80}")
        print("To view a specific request-response pair:")
        print(f"  python {sys.argv[0]} --pair <request_id>")
        print(f"{'='*80}\n")


if __name__ == "__main__":
    main()
