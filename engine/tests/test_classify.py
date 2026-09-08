"""Run: python -m engine.tests.test_classify"""
from __future__ import annotations

from engine.classify import classify

SHOULD_MATCH = [
    ("Senior Product Designer", "Design"),
    ("Product Designer, Growth", ""),
    ("Staff Designer", "Product"),
    ("UX Designer II", ""),
    ("Design Systems Lead", "Design"),
    ("Head of Design", ""),
    ("Design Engineer", "Engineering"),
    ("UX Researcher", "Research"),
    ("Content Designer", "Design"),
    ("Group Product Manager", "Product"),
    ("Principal PM, Payments", ""),
    ("Designer", "Design"),               # bare title, design dept
    ("Brand Designer", "Marketing"),
]

SHOULD_NOT_MATCH = [
    ("Instructional Designer", "People"),
    ("Mechanical Design Engineer", "Hardware"),
    ("Physical Design Engineer", "Silicon"),
    ("Game Designer", "Studio"),
    ("Product Marketing Manager", "Marketing"),
    ("Program Manager, Design", "Design"),
    ("Product Analyst", "Data"),
    ("Account Executive", "Sales"),
    ("Senior Software Engineer", "Engineering"),
    ("Design Verification Engineer", "Silicon"),
    ("Interior Designer", "Facilities"),
    ("Designer", "Sales"),                # bare title, wrong dept
    # real false positives found in the first ingest (2026-09-07):
    ("Data Center Design Engineer, Electrical - Industrial Compute", "Infrastructure"),
    ("Actuator Design Engineer", "Robotics"),
    ("Actuator Electromagnetic Design Engineer", "Hardware"),
    ("Lead Mechanical/ Product Design Engineer, Special Projects", "Hardware"),
    ("Manager, Software Engineering, Fullstack (Repayment UX Engineer)", "Engineering"),
]


def run():
    fails = 0
    for title, dept in SHOULD_MATCH:
        ok, fam, reason = classify(title, dept)
        if not ok:
            fails += 1
            print("  MISS (want match)  {!r} / {!r}  -> {}".format(title, dept, reason))
    for title, dept in SHOULD_NOT_MATCH:
        ok, fam, reason = classify(title, dept)
        if ok:
            fails += 1
            print("  MISS (want reject) {!r} / {!r}  -> {} ({})".format(title, dept, fam, reason))
    total = len(SHOULD_MATCH) + len(SHOULD_NOT_MATCH)
    print("{}/{} classifier cases pass".format(total - fails, total))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
