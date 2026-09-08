"""
Vertical filter: is this posting a product-design (or adjacent) role?

Beta vertical = "the people who design digital products":
  design      product / UX / UI / visual / brand / interaction / motion designers,
              design systems, design leadership
  design-eng  design engineers / design technologists / UX engineers
  research    UX / product / design researchers
  pm          product managers / product leadership   (toggle with INCLUDE_PM)

Rules-first on purpose: it is auditable, fast, and free. A small model can be added later
as a tie-breaker for the "no-match" bucket, never as the primary decision.
"""
from __future__ import annotations

import re

INCLUDE_PM = True

_DESIGN = [
    (r"\bproduct design", "design"),
    (r"\bux/?ui design|\bui/?ux design", "design"),
    (r"\bux design|\buser experience design", "design"),
    (r"\bui design|\bvisual design|\binteraction design|\bmotion design", "design"),
    (r"\bbrand design|\bcommunication design|\bgraphic design", "design"),
    (r"\bdesign system", "design"),
    (r"\bdesign ops|\bdesignops|\bux ops", "design"),
    (r"\bhead of design|\bdesign director|\bdirector of design|\bvp,? design", "design"),
    (r"\bdesign manager|\bdesign lead|\blead product designer|\bgroup design", "design"),
    (r"\bstaff designer\b|\bprincipal designer\b|\bsenior designer\b|\bdesigner ii?i?\b", "design"),
    (r"\bproduct designer\b|\bux designer\b|\bui designer\b|\bux researcher and designer", "design"),
    (r"\bdesign engineer|\bdesign technologist|\bux engineer|\bui engineer", "design-eng"),
    (r"\bux research|\buser research|\bdesign research|\bresearch ops|\bux writer|\bux writing|\bcontent design", "research"),
]

_PM = [
    (r"\bproduct manager\b|\bproduct management\b|\bgroup product manager\b|\bgpm\b", "pm"),
    (r"\bhead of product\b|\bdirector,? product\b|\bdirector of product\b|\bvp,? product\b", "pm"),
    (r"\bprincipal pm\b|\bsenior pm\b|\blead pm\b|\bstaff product manager\b", "pm"),
    (r"\bproduct lead\b|\bchief product officer\b|\bcpo\b", "pm"),
]

# Hard excludes — words that co-occur with "design"/"product"/"engineer" but are not our
# vertical. Order-independent; any hit short-circuits to "not a target role".
_EXCLUDE = [
    r"instructional design|learning design|curriculum design|training design",
    # physical / hardware / silicon engineering that borrows the word "design"
    r"mechanical|electrical|hardware design|firmware|chip design|silicon|asic|rtl|fpga",
    r"circuit design|pcb|analog design|physical design|design verification|design for test",
    r"industrial design|cad\b|solidworks|actuator|electromagnet|\bgear design|thermal design",
    r"data ?cent(er|re)|antenna|\brf design|optical design|structural design",
    # other design disciplines that aren't digital-product design
    r"game design|level design|narrative design|systems design engineer",
    r"interior design|set design|lighting design|landscape design|floral|floor plan",
    r"packaging design|print production|prepress|apparel design|textile|jewelry",
    # eng-management roles that only match because a design-adjacent team is named
    r"manager,? software engineering|software engineering,",
    # "product" roles that are not product management
    r"data product|product marketing|product counsel|product support|product specialist",
    r"product operations analyst|product analyst|product security|technical product marketing",
    r"pmo\b|program manager|project manager|portfolio manager|product owner \(scrum",
    r"sales|account executive|business development|solutions engineer|customer success",
    r"design partner|design win|design services engineer",
]

_EX_RE = re.compile("|".join(_EXCLUDE), re.I)


def classify(title: str, department: str = ""):
    """
    Returns (is_target: bool, role_family: str|None, reason: str).
    """
    t = " " + re.sub(r"\s+", " ", (title or "").lower()).strip() + " "
    d = (department or "").lower().strip()

    if _EX_RE.search(t):
        m = _EX_RE.search(t)
        return False, None, "exclude:" + m.group(0)

    for pat, fam in _DESIGN:
        if re.search(pat, t):
            return True, fam, "title:" + pat
    if INCLUDE_PM:
        for pat, fam in _PM:
            if re.search(pat, t):
                return True, fam, "title:" + pat

    # Department fallback: a bare "Designer"/"Design" title sitting in a Design/Product org.
    if d in {"design", "product design", "ux", "user experience", "design & research",
             "product & design", "brand", "creative"} and re.search(r"\bdesign(er)?\b|\bux\b", t):
        return True, "design", "dept:" + d

    return False, None, "no-match"
