"""The built frontend, as the host actually serves it.

Every other test here covers the Python half. This one covers the failure that
only appears in a real install: a wheel with a working backend, a registered
section, and no interface. It installs cleanly, answers every API call, and the
board simply never appears.

That failure has three distinct causes, and each is asserted below rather than
assumed:

* the bundle isn't in the package at all (nobody ran the frontend build);
* the bundle is there but the host won't serve it;
* the bundle is served but was compiled wrong — most importantly with its own
  copy of React, which would put a second dispatcher on the page and make every
  hook in this plugin throw.

Out of tree there is a fourth, added here: the bundle must now carry its own
Tailwind utilities, because the host's stylesheet no longer scans these sources.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from precursor.backend.main import create_app
from precursor_kanban import SECTION_ID

# The bundle is a build product (`make build`), so a bare `pytest` in a fresh
# checkout has nothing to look at. CI builds it before running the suite, which
# is what keeps these from being permanently skipped.
BUNDLE = Path(__file__).resolve().parents[1] / "src" / "precursor_kanban" / "web" / "index.js"

pytestmark = pytest.mark.skipif(
    not BUNDLE.is_file(),
    reason="frontend bundle not built — run `make build`",
)


@pytest.fixture(scope="module")
def bundle() -> str:
    return BUNDLE.read_text(encoding="utf-8")


def test_the_host_advertises_and_serves_the_bundle() -> None:
    """The descriptor points at a URL that actually returns the module."""
    app = create_app()
    with TestClient(app) as client:
        descriptors = client.get("/api/plugins").json()
        section = next(d for d in descriptors if d["id"] == SECTION_ID)

        entry = section["entry"]
        assert entry == f"/api/plugins/{SECTION_ID}/assets/index.js"

        served = client.get(entry)
        assert served.status_code == 200
        # Browsers refuse to `import` a module served as anything else.
        assert "javascript" in served.headers["content-type"]
        assert served.text == BUNDLE.read_text(encoding="utf-8")


def test_the_bundle_borrows_the_hosts_react(bundle: str) -> None:
    """React and the SDK stay external, resolved by the host's import map.

    A bundled React is the one build mistake that cannot be caught by types, a
    passing build, or any backend test — it fails at the first hook call, in the
    user's browser.
    """
    for specifier in ('"react"', '"react/jsx-runtime"', '"@precursor/host"'):
        assert f"from {specifier}" in bundle, f"{specifier} should be imported, not bundled"

    # React's own build banner would ride along if it had been vendored.
    assert "react-dom.production" not in bundle


def test_the_bundle_carries_its_own_styles(bundle: str) -> None:
    """The utilities this plugin uses, mapped onto the host's theme tokens.

    In the monorepo the host's Tailwind build scanned these sources and its
    stylesheet already contained them. It cannot now, so the bundle ships them —
    and it must do so *through* the host's variables, or the board would keep a
    second, drifting copy of the palette and stop following dark mode.
    """
    for utility in (".text-muted", ".bg-surface", ".border-border"):
        assert utility in bundle, f"{utility} missing — did the stylesheet stop being built?"

    assert "--color-surface:var(--surface)" in bundle
    assert ":where(.dark,.dark *)" in bundle
