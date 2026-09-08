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
    # real false positives found in the classifier audit (2026-09-08):
    ("Physical Security Design Lead and Contract Document Specialist", "Security"),
    ("Policy Design Manager, Conventional Weapons", "Policy"),
    ("Executive Assistant, Design", "Design"),
    ("People Partner - Product and Product Design", "People"),
    ("Senior Android Engineer, Design System", "Engineering"),
    ("Senior Frontend Engineer - Design Systems", "Engineering"),
    ("Member of Technical Staff (Software Engineer, Design System)", "Engineering"),
    ("CMF Designer II (Accessories & Apparel)", "Industrial Design"),
    ("Senior Project Specialist, Retail Design", "Retail"),
]

# (title, department) -> expected family. Guards the design/pm boundary both ways.
WANT_FAMILY = [
    ("Senior Product Manager, Design Systems", "", "pm"),
    ("Product Manager, Design Tooling", "Product", "pm"),
    ("Director, Product Design", "Design", "design"),        # not pm
    ("Product Design Manager, Payroll", "Design", "design"),  # not pm
    ("Design Systems Engineer", "Design", "design-eng"),      # not excluded by "X engineer"
    ("UX Engineer", "Design", "design-eng"),
    ("Design Engineer", "Engineering", "design-eng"),
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
    for title, dept, want in WANT_FAMILY:
        ok, fam, reason = classify(title, dept)
        if not ok or fam != want:
            fails += 1
            print("  MISS (want {})  {!r}  -> ok={} fam={} ({})".format(want, title, ok, fam, reason))
    total = len(SHOULD_MATCH) + len(SHOULD_NOT_MATCH) + len(WANT_FAMILY)
    print("{}/{} classifier cases pass".format(total - fails, total))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
