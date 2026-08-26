#!/usr/bin/env python3
"""Validate ticket-system signature attestations for a regional-DR change.

This tool never reads a mailbox or treats an email signature as identity proof.
It consumes JSON records exported by an approved ticketing/signature system and,
in production mode, requires an external verifier command to validate each record.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

PLACEHOLDER = re.compile(
    r"fictional|do-not-use|DEMO-NOT-AUTHORIZED|SAMPLE-NONPROD|REQUIRED_FROM|To be assigned",
    re.IGNORECASE,
)
RECORD_KEYS = {"oidc", "evidenceRetention", "routing"}
REF_PATTERN = re.compile(r"^(urn:[A-Za-z0-9:._/-]+|ticket:[A-Za-z0-9:._/-]+)$")
DIGEST_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")


class ValidationError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--records", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument(
        "--production",
        action="store_true",
        help="Require the configured external signature verifier for every record.",
    )
    parser.add_argument(
        "--signature-verifier",
        type=Path,
        help="Executable called as <verifier> <record.json>; exit 0 means signature verified.",
    )
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValidationError(f"JSON document must be an object: {path}")
    return data


def reject_placeholders(value: Any, location: str) -> None:
    if isinstance(value, str) and (not value.strip() or PLACEHOLDER.search(value)):
        raise ValidationError(f"unresolved or fictional value at {location}")
    if isinstance(value, dict):
        for key, item in value.items():
            reject_placeholders(item, f"{location}.{key}")
    if isinstance(value, list):
        for index, item in enumerate(value):
            reject_placeholders(item, f"{location}[{index}]")


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def parse_signed_at(value: Any) -> None:
    if not isinstance(value, str):
        raise ValidationError("signedAt must be an ISO-8601 string")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValidationError("signedAt must be ISO-8601") from exc


def verify_external(verifier: Path, record_path: Path) -> None:
    if not verifier.is_file() or not os.access(verifier, os.X_OK):
        raise ValidationError("signature verifier is missing or not executable")
    result = subprocess.run([str(verifier), str(record_path)], check=False, capture_output=True, text=True)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "external signature verification failed").strip()
        raise ValidationError(message)


def validate_policy(policy: dict[str, Any]) -> tuple[str, dict[str, dict[str, str]]]:
    reject_placeholders(policy, "policy")
    if policy.get("schemaVersion") != "1.0":
        raise ValidationError("policy schemaVersion must be 1.0")
    change_id = policy.get("changeId")
    if not isinstance(change_id, str):
        raise ValidationError("policy changeId must be a string")
    approvals = policy.get("approvals")
    if not isinstance(approvals, dict) or set(approvals) != RECORD_KEYS:
        raise ValidationError("policy approvals must contain exactly oidc, evidenceRetention, and routing")
    normalized: dict[str, dict[str, str]] = {}
    for record_type, requirement in approvals.items():
        if not isinstance(requirement, dict):
            raise ValidationError(f"policy approval {record_type} must be an object")
        owner_role = requirement.get("ownerRole")
        document_path = requirement.get("documentPath")
        if not isinstance(owner_role, str) or not isinstance(document_path, str):
            raise ValidationError(f"policy approval {record_type} needs ownerRole and documentPath")
        path = Path(document_path)
        if not path.is_file():
            raise ValidationError(f"approval document is unavailable for {record_type}")
        normalized[record_type] = {
            "ownerRole": owner_role,
            "documentPath": document_path,
            "documentSha256": digest(path),
        }
    return change_id, normalized


def validate_record(
    record: dict[str, Any], record_path: Path, change_id: str, requirement: dict[str, str], production: bool, verifier: Path | None
) -> dict[str, str]:
    if record.get("schemaVersion") != "1.0":
        raise ValidationError(f"{record_path.name}: schemaVersion must be 1.0")
    if record.get("changeId") != change_id:
        raise ValidationError(f"{record_path.name}: changeId does not match policy")
    if record.get("recordType") not in RECORD_KEYS:
        raise ValidationError(f"{record_path.name}: invalid recordType")
    if record.get("ownerRole") != requirement["ownerRole"]:
        raise ValidationError(f"{record_path.name}: ownerRole does not match policy")
    if record.get("decision") != "APPROVED":
        raise ValidationError(f"{record_path.name}: decision must be APPROVED")
    if record.get("documentSha256") != requirement["documentSha256"]:
        raise ValidationError(f"{record_path.name}: approval document digest does not match")
    if not DIGEST_PATTERN.fullmatch(str(record.get("documentSha256"))):
        raise ValidationError(f"{record_path.name}: documentSha256 is malformed")
    parse_signed_at(record.get("signedAt"))
    signature_ref = record.get("signatureVerificationRef")
    if not isinstance(signature_ref, str) or not REF_PATTERN.fullmatch(signature_ref):
        raise ValidationError(f"{record_path.name}: signatureVerificationRef is invalid")
    if record.get("signatureVerificationStatus") != "VERIFIED":
        raise ValidationError(f"{record_path.name}: signatureVerificationStatus must be VERIFIED")
    if production:
        if verifier is None:
            raise ValidationError("production mode requires --signature-verifier")
        verify_external(verifier, record_path)
    return {
        "recordType": str(record["recordType"]),
        "ownerRole": str(record["ownerRole"]),
        "signedAt": str(record["signedAt"]),
        "signatureVerificationRef": signature_ref,
        "documentSha256": str(record["documentSha256"]),
    }


def main() -> int:
    args = parse_args()
    policy = read_json(args.policy)
    change_id, requirements = validate_policy(policy)
    if not args.records.is_dir():
        raise ValidationError("records directory is unavailable")

    collected: dict[str, dict[str, str]] = {}
    for record_path in sorted(args.records.glob("*.json")):
        record = read_json(record_path)
        record_type = record.get("recordType")
        if record_type not in requirements:
            raise ValidationError(f"{record_path.name}: recordType is not required")
        if record_type in collected:
            raise ValidationError(f"duplicate approval record for {record_type}")
        collected[record_type] = validate_record(
            record, record_path, change_id, requirements[record_type], args.production, args.signature_verifier
        )

    missing = RECORD_KEYS - set(collected)
    if missing:
        raise ValidationError("missing required approval records: " + ", ".join(sorted(missing)))

    args.evidence.mkdir(parents=True, exist_ok=True)
    if args.evidence.is_symlink():
        raise ValidationError("evidence directory must not be a symlink")
    args.evidence.chmod(0o700)
    summary = {
        "schemaVersion": "1.0",
        "changeId": change_id,
        "validationMode": "production-external-verifier" if args.production else "local-structure-only",
        "approvals": [collected[key] for key in sorted(collected)],
        "warning": "Local structure-only mode does not cryptographically verify signatures. Use --production with an approved external verifier before change submission.",
    }
    output = args.evidence / "owner-approval-validation-summary.json"
    output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    output.chmod(0o600)
    print("OWNER_APPROVAL_RECORDS_VALIDATION_PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValidationError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
