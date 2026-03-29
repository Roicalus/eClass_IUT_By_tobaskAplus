#!/usr/bin/env python
"""Import students and group memberships from an .xlsx file into Firestore.

Expected columns (case-insensitive, spaces ignored):
- Group: e.g. CIE-25-01
- Student ID: e.g. U2510002
- Name in Full: e.g. SHOMURODOV JALOLIDDIN

This script UPSERTs:
- /students/{studentId}: { fullName, updatedAt }
- /groups/{groupId}: { studentIds, faculty, year, number, updatedAt }

Auth:
- Requires a Firebase service account JSON via GOOGLE_APPLICATION_CREDENTIALS.

Usage examples:
  python tools/import_students_from_xlsx.py --xlsx list.xlsx --project eclassiut --dry-run
  python tools/import_students_from_xlsx.py --xlsx list.xlsx --project eclassiut

Notes:
- Rejects group numbers '00' for new-format group ids.
- Does not delete anything.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


def _normalize_header(s: str) -> str:
    # Keep Unicode word characters so Cyrillic headers survive normalization.
    # Examples: "Группа" -> "группа", "ID Студента" -> "idстудента".
    t = (s or "").strip().lower()
    t = re.sub(r"\W+", "", t, flags=re.UNICODE)
    return t.replace("_", "")


HEADER_ALIASES = {
    "group": {"group", "groupid", "groupname", "группа"},
    "student_id": {
        "studentid",
        "student",
        "id",
        "studentnumber",
        "studentcode",
        "idстудента",
        "идстудента",
    },
    "full_name": {"name", "fullname", "nameinfull", "studentname", "полноеимя", "фио"},
}


GROUP_RE = re.compile(r"^([A-Z0-9]{2,10})-(\d{2})-(\d{2})$")


@dataclass(frozen=True)
class Row:
    group_id: str
    student_id: str
    full_name: str


def _parse_group_parts(group_id: str) -> Optional[Tuple[str, str, str]]:
    m = GROUP_RE.match(group_id.strip().upper())
    if not m:
        return None
    return (m.group(1), m.group(2), m.group(3))


def _normalize_group_id(raw: str) -> str:
    # Keep only the canonical characters used in our id format.
    # Example: "**CIE-25-16" -> "CIE-25-16".
    t = (raw or "").strip().upper()
    t = re.sub(r"[^A-Z0-9-]", "", t)
    return t


def _read_rows_xlsx(path: str) -> List[Row]:
    try:
        import openpyxl  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Missing dependency 'openpyxl'. Install with: pip install openpyxl"
        ) from e

    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb.active

    rows_iter = ws.iter_rows(values_only=True)
    try:
        header = next(rows_iter)
    except StopIteration:
        return []

    header_norm = [_normalize_header(str(c) if c is not None else "") for c in header]

    def find_col(target_key: str) -> int:
        aliases = HEADER_ALIASES[target_key]
        for idx, h in enumerate(header_norm):
            if h in aliases:
                return idx
        raise ValueError(
            f"Cannot find column for {target_key}. Found headers: {list(header_norm)}"
        )

    gi = find_col("group")
    si = find_col("student_id")
    ni = find_col("full_name")

    out: List[Row] = []
    for r in rows_iter:
        group_id = (str(r[gi]) if gi < len(r) and r[gi] is not None else "").strip()
        student_id = (str(r[si]) if si < len(r) and r[si] is not None else "").strip()
        full_name = (str(r[ni]) if ni < len(r) and r[ni] is not None else "").strip()

        if not group_id and not student_id and not full_name:
            continue

        if not group_id or not student_id or not full_name:
            raise ValueError(
                f"Bad row (missing fields): group={group_id!r}, student={student_id!r}, name={full_name!r}"
            )

        out.append(
            Row(
                group_id=_normalize_group_id(group_id),
                student_id=student_id.strip(),
                full_name=full_name.strip(),
            )
        )

    return out


def _validate_rows(rows: Sequence[Row]) -> None:
    bad: List[str] = []
    for i, row in enumerate(rows, start=2):  # +1 header, 1-indexed -> starts at 2
        parts = _parse_group_parts(row.group_id)
        if parts is None:
            bad.append(f"Row {i}: invalid group id {row.group_id!r}")
            continue
        faculty, year, number = parts
        if number == "00":
            bad.append(f"Row {i}: group number cannot be 00 ({row.group_id})")
        if not row.student_id:
            bad.append(f"Row {i}: empty student id")
        if not row.full_name:
            bad.append(f"Row {i}: empty full name")

    if bad:
        raise ValueError("\n".join(bad))


def _build_documents(rows: Sequence[Row]) -> Tuple[Dict[str, str], Dict[str, Set[str]]]:
    students: Dict[str, str] = {}
    groups: Dict[str, Set[str]] = {}

    for row in rows:
        sid = row.student_id.strip()
        if sid in students and students[sid] != row.full_name:
            # Prefer the latest non-empty name, but warn.
            print(
                f"WARN: student {sid} has conflicting names: {students[sid]!r} vs {row.full_name!r}. Using latest.",
                file=sys.stderr,
            )
        students[sid] = row.full_name

        gid = row.group_id.strip().upper()
        groups.setdefault(gid, set()).add(sid)

    return students, groups


def _init_firestore(project_id: str, credentials_path: Optional[str]):
    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials, firestore  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "Missing dependency 'firebase-admin'. Install with: pip install firebase-admin"
        ) from e

    # Reuse if already initialized.
    if not firebase_admin._apps:
        if credentials_path:
            if not os.path.exists(credentials_path):
                raise RuntimeError(f"Credentials file not found: {credentials_path}")
            cred = credentials.Certificate(credentials_path)
        else:
            if not os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
                raise RuntimeError(
                    "GOOGLE_APPLICATION_CREDENTIALS is not set and --credentials was not provided. "
                    "Provide --credentials <path-to-service-account.json> (recommended)."
                )
            cred = credentials.ApplicationDefault()
        firebase_admin.initialize_app(cred, {"projectId": project_id})

    return firestore.client()


def _chunked(items: List[Tuple[str, dict]], size: int) -> Iterable[List[Tuple[str, dict]]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _upsert_students(db, students: Dict[str, str], dry_run: bool) -> int:
    from google.cloud.firestore import SERVER_TIMESTAMP  # type: ignore

    col = db.collection("students")
    ops: List[Tuple[str, dict]] = []

    for sid, name in students.items():
        sid = sid.strip()
        name = name.strip()
        if not sid or not name:
            continue
        ops.append(
            (
                sid,
                {
                    "fullName": name,
                    "updatedAt": SERVER_TIMESTAMP,
                },
            )
        )

    if dry_run:
        return len(ops)

    written = 0
    for chunk in _chunked(ops, 400):
        batch = db.batch()
        for sid, data in chunk:
            batch.set(col.document(sid), data, merge=True)
        batch.commit()
        written += len(chunk)

    return written


def _upsert_groups(db, groups: Dict[str, Set[str]], dry_run: bool) -> int:
    from google.cloud.firestore import SERVER_TIMESTAMP  # type: ignore

    col = db.collection("groups")
    ops: List[Tuple[str, dict]] = []

    for gid, members in groups.items():
        gid_norm = gid.strip().upper()
        parts = _parse_group_parts(gid_norm)
        if parts is None:
            continue
        faculty, year, number = parts
        if number == "00":
            continue

        student_ids = sorted({m.strip() for m in members if m.strip()})

        ops.append(
            (
                gid_norm,
                {
                    "faculty": faculty,
                    "year": year,
                    "number": number,
                    "studentIds": student_ids,
                    "updatedAt": SERVER_TIMESTAMP,
                },
            )
        )

    if dry_run:
        return len(ops)

    written = 0
    for chunk in _chunked(ops, 200):
        batch = db.batch()
        for gid, data in chunk:
            batch.set(col.document(gid), data, merge=True)
        batch.commit()
        written += len(chunk)

    return written


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--xlsx", required=True, help="Path to .xlsx file")
    ap.add_argument(
        "--project",
        required=True,
        help="Firebase project id (the one that hosts /students and /groups)",
    )
    ap.add_argument(
        "--credentials",
        help=(
            "Path to a Firebase service account JSON file. "
            "If omitted, GOOGLE_APPLICATION_CREDENTIALS must be set."
        ),
    )
    ap.add_argument("--dry-run", action="store_true", help="Do not write")

    args = ap.parse_args(list(argv))

    xlsx_path = args.xlsx
    if not os.path.exists(xlsx_path):
        print(f"File not found: {xlsx_path}", file=sys.stderr)
        return 2

    rows = _read_rows_xlsx(xlsx_path)
    if not rows:
        print("No data rows found.")
        return 0

    _validate_rows(rows)
    students, groups = _build_documents(rows)

    print(
        f"Parsed {len(rows)} rows -> {len(students)} students, {len(groups)} groups"
    )

    if args.dry_run:
        # Still validate dependencies without initializing firestore.
        return 0

    db = _init_firestore(args.project, args.credentials)

    student_writes = _upsert_students(db, students, dry_run=False)
    group_writes = _upsert_groups(db, groups, dry_run=False)

    print(f"Wrote/updated: {student_writes} students, {group_writes} groups")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
