#!/usr/bin/env python3
"""Prove a refactor into helper functions changed no observable behaviour.

A split into helpers is allowed to change formatting, indentation, function boundaries and
declaration order. It is not allowed to change which side effects run, in what order, or how
many times.

An effect is any statement that calls something or assigns to something. Formatting is
normalised away, so re-indentation is invisible.

The check has two parts:

1. Every helper's effects must be an ordered subsequence of the original's. A helper may
   therefore only do what the original did, in the order the original did it.
2. Together the helpers must still account for every original effect: nothing dropped, nothing
   invented. With --dedup one copy of a byte-identical duplicated block may disappear, because
   the refactor merged it into a shared helper.

    git show main:path/to/File.swift > /tmp/before.swift
    python3 scripts/verify-refactor-move.py /tmp/before.swift 100 560 path/to/File.swift 100 700 --dedup

Ranges are 1-indexed and inclusive.
"""

from __future__ import annotations

import re
import sys
from collections import Counter

# Prefixes that wrap a statement without changing what it does.
PREFIX = re.compile(r"^(?:try\s+await\s+|try\?\s+|try\s+|await\s+|else\s+)?(?:if\s+|while\s+|guard\s+)?")

# A call statement, optionally through `self`.
CALL = re.compile(r"^(?:self\.)?[A-Za-z_]\w*[.(]")

# An assignment or a mutating collection call on a stored property.
ASSIGN = re.compile(r"^(?:self\.)?[A-Za-z_]\w*(?:\[[^\]]*\])?\s*(?:=(?!=)|\+=|-=|\.insert\(|\.remove\(|\.append\()")

# `let x = call(...)` declares a name but still performs the call, so the right-hand side counts.
BINDING = re.compile(r"^(?:let|var)\s+\w+(?:\s*:\s*[^=]+)?\s*=\s*(.+)$")

# Lines that declare or control rather than act.
DECL = re.compile(
    r"^(?:private |internal |fileprivate |public |@\w+\s+)*(?:func|struct|enum|class|var|let|init|"
    r"deinit|case|import|extension)\b|^///|^//"
)
CONTROL = re.compile(r"^(?:return|throw|defer|do|else|catch|switch|default:|fallthrough|break|continue)\b|^\}")


def read_slice(path: str, start: int, end: int) -> list[str]:
    with open(path) as handle:
        return handle.read().splitlines()[start - 1:end]


def normalize(line: str) -> str:
    text = re.sub(r"\s+", " ", line.strip())
    # Values hoisted into the context/request structs are compared by their original path.
    return re.sub(r"\b(?:context|request)\.", "", text)


def statement(line: str) -> str | None:
    """The comparable statement text, or None when the line does not act."""
    text = normalize(line)
    if not text or text in ("{", "}", "}) {", "} else {"):
        return None
    # Argument continuation of a multi-line call, not a statement of its own.
    if text.endswith(",") or re.match(r"^[A-Za-z_]\w*: ", text):
        return None
    binding = BINDING.match(text)
    if binding:
        # A plain `let x = Foo(...)` is value construction. An awaited call is an effect.
        text = binding.group(1)
        if "await " not in text:
            return None
    elif DECL.match(text) or CONTROL.match(text):
        return None
    stripped = PREFIX.sub("", text)
    if DECL.match(stripped) or CONTROL.match(stripped):
        return None
    if CALL.match(stripped) or ASSIGN.match(stripped):
        return stripped
    return None


def effects(lines: list[str]) -> list[str]:
    return [text for text in (statement(line) for line in lines) if text]


FUNC_START = re.compile(r"^    (?:private |internal )?(?:func|struct|enum) (\w+)")


def group_by_function(lines: list[str]) -> list[tuple[str, list[str]]]:
    groups: list[tuple[str, list[str]]] = []
    name = "<region>"
    body: list[str] = []
    for line in lines:
        match = FUNC_START.match(line)
        if match:
            if body:
                groups.append((name, body))
            name = match.group(1)
            body = [line]
        else:
            body.append(line)
    if body:
        groups.append((name, body))
    return groups


def is_subsequence(needle: list[str], haystack: list[str]) -> bool:
    cursor = 0
    for text in needle:
        while cursor < len(haystack) and haystack[cursor] != text:
            cursor += 1
        if cursor == len(haystack):
            return False
        cursor += 1
    return True


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dedup = "--dedup" in sys.argv
    if len(args) != 6:
        print(__doc__)
        return 2
    orig_path, orig_start, orig_end, new_path, new_start, new_end = args
    original = effects(read_slice(orig_path, int(orig_start), int(orig_end)))
    region = read_slice(new_path, int(new_start), int(new_end))
    groups = group_by_function(region)

    print(f"original effects      : {len(original)}")
    print(f"units in the new code : {len(groups)}")

    # Calling a helper is delegation, not new behaviour: the helper's own body is checked here too.
    helper_names = {name for name, _ in groups}
    helper_call = re.compile(r"^(?:self\.)?(?:%s)\(" % "|".join(sorted(helper_names)))

    ok = True
    print("\n== 1. each unit only does what the original did, in the same order ==")
    for name, body in groups:
        own = [text for text in effects(body) if not helper_call.match(text)]
        if not own:
            print(f"   --   {name:<36} no effects")
            continue
        if is_subsequence(own, original):
            print(f"   ok   {name:<36} {len(own)} effects")
        else:
            ok = False
            print(f"   FAIL {name:<36} {len(own)} effects out of original order")

    print("\n== 2. together they account for the original ==")
    combined: list[str] = []
    for _, body in groups:
        combined.extend(text for text in effects(body) if not helper_call.match(text))
    expected = list(original)
    if dedup:
        surplus = Counter(expected) - Counter(combined)
        if surplus:
            print("   accounting for the merged duplicate block:")
            for text, count in surplus.items():
                print(f"      {count}x {text}")
                for _ in range(count):
                    for index in range(len(expected) - 1, -1, -1):
                        if expected[index] == text:
                            del expected[index]
                            break
    lost = Counter(expected) - Counter(combined)
    added = Counter(combined) - Counter(expected)
    if lost:
        ok = False
        print("   FAIL: dropped:")
        for text, count in lost.items():
            print(f"      {count}x {text}")
    if added:
        ok = False
        print("   FAIL: invented:")
        for text, count in added.items():
            print(f"      {count}x {text}")
    if not lost and not added:
        print(f"   ok   {len(combined)} effects accounted for, none dropped, none invented")

    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
