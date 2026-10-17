"""Command-line options for the e2e suite (tests/e2e).

They live in the root conftest because pytest parses the command line before
it loads tests/e2e/conftest.py when no test path is given (`pytest --lc-...`).
"""
import os
from pathlib import Path

import pytest

E2E_DIR = Path(__file__).resolve().parent / 'tests' / 'e2e'


def pytest_addoption(parser):
    g = parser.getgroup('leetcode.vim e2e')
    g.addoption('--lc-mode', choices=['replay', 'live'],
                default=os.environ.get('LEETCODE_E2E_MODE', 'replay'),
                help='replay: answer from fixtures (default). live: proxy to the real site.')
    g.addoption('--lc-fixtures', default=str(E2E_DIR / 'fixtures' / 'legacy'),
                help='fixture directory used in replay mode')
    g.addoption('--lc-upstream', default=os.environ.get('LEETCODE_E2E_UPSTREAM',
                                                        'https://leetcode.com'),
                help='site to proxy to in live mode')
    g.addoption('--lc-record', default=None,
                help='live mode: save every response as a fixture in this directory')
    g.addoption('--lc-backend', choices=['all', 'python', 'vim'],
                default=os.environ.get('LEETCODE_E2E_BACKEND', 'all'),
                help='plugin backend(s) to test: Python or Vim script')
    g.addoption('--lc-editor', choices=['all', 'vim', 'nvim'],
                default=os.environ.get('LEETCODE_E2E_EDITOR', 'all'),
                help='editor(s) to run the plugin in; "all" runs each installed one')
    g.addoption('--lc-allow-submit', action='store_true',
                help='live mode: allow tests that create real submissions on your account')


@pytest.hookimpl(tryfirst=True)
def pytest_cmdline_main(config):
    # Replay mode runs tests in parallel (-n auto in pytest.ini); live mode
    # doesn't, so leetcode.com isn't hit by several editors at once.
    if config.getoption('--lc-mode') == 'live' and hasattr(config.option, 'numprocesses'):
        config.option.numprocesses = 0
        config.option.dist = 'no'
