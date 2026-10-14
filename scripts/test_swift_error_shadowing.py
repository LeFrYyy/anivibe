#!/usr/bin/env python3
"""Source regression for the reported Swift catch shadowing failure; not a Swift compiler."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'Anivibe/Features/Community/WatchRoomViews.swift'


def shadowed_assignments(source):
    """Check the simple default-catch blocks used by this view for bare error assignments."""
    result = []
    for match in re.finditer(r'\bcatch\s*\{', source):
        start = match.end()
        depth, end = 1, start
        while end < len(source) and depth:
            if source[end] == '{':
                depth += 1
            elif source[end] == '}':
                depth -= 1
            end += 1
        body = source[start:end - 1]
        for assignment in re.finditer(r'(?<![\w.])error\s*=(?!=)', body):
            result.append(source.count('\n', 0, start + assignment.start()) + 1)
    return result


class SwiftCatchShadowingTests(unittest.TestCase):
    def test_watch_room_never_assigns_to_implicit_catch_error(self):
        source = TARGET.read_text(encoding='utf-8')
        self.assertTrue(re.search(r'\bcatch\s*\{', source))
        self.assertEqual(shadowed_assignments(source), [], 'Use self.error for the @State property inside catch')
        self.assertIn('self.error = CommunityStore.message(error)', source)

    def test_guard_detects_the_reported_failure(self):
        broken = '} catch { if !Task.isCancelled { error = CommunityStore.message(error) } }'
        fixed = '} catch { if !Task.isCancelled { self.error = CommunityStore.message(error) } }'
        self.assertEqual(len(shadowed_assignments(broken)), 1)
        self.assertEqual(shadowed_assignments(fixed), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
