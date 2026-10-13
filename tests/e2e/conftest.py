import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent / 'lib'))

from fake_leetcode import FakeLeetCode  # noqa: E402
from vim_driver import REPO_ROOT, Scenario  # noqa: E402

E2E_DIR = Path(__file__).resolve().parent
CACHE_DIR = REPO_ROOT / '.e2e-cache'
VIM_REQUIREMENTS = E2E_DIR / 'vim-requirements.txt'

# Fake credentials used against the replay server.
REPLAY_COOKIES = {'LEETCODE_SESSION': 'e2e-session', 'csrftoken': 'e2e-csrf'}


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
    g.addoption('--lc-allow-submit', action='store_true',
                help='live mode: allow tests that create real submissions on your account')


def pytest_configure(config):
    config.addinivalue_line('markers', 'replay_only: needs fixture data; skipped in live mode')
    config.addinivalue_line('markers', 'live_only: only meaningful against the real site')
    config.addinivalue_line('markers', 'submits: creates a real submission in live mode')


def pytest_collection_modifyitems(config, items):
    mode = config.getoption('--lc-mode')
    allow_submit = config.getoption('--lc-allow-submit')
    for item in items:
        if mode == 'live' and 'replay_only' in item.keywords:
            item.add_marker(pytest.mark.skip(reason='replay-only test'))
        if mode == 'replay' and 'live_only' in item.keywords:
            item.add_marker(pytest.mark.skip(reason='live-only test (use --lc-mode=live)'))
        if mode == 'live' and 'submits' in item.keywords and not allow_submit:
            item.add_marker(pytest.mark.skip(reason='creates a real submission; '
                                                    'pass --lc-allow-submit'))


# ---- Vim and its Python ------------------------------------------------------

def _vim_python_version():
    if not shutil.which('vim'):
        pytest.exit('vim is not installed', returncode=4)
    probe = CACHE_DIR / 'vim-python-version'
    CACHE_DIR.mkdir(exist_ok=True)
    subprocess.run(['vim', '-N', '-u', 'NONE', '-i', 'NONE', '-es',
                    '-c', 'py3 import sys; open(r"{}", "w").write("%d.%d" % sys.version_info[:2])'
                    .format(probe),
                    '-c', 'qa!'], stdin=subprocess.DEVNULL, timeout=30)
    if not probe.exists():
        pytest.exit('vim has no working +python3 support', returncode=4)
    return probe.read_text().strip()


@pytest.fixture(scope='session')
def vim_python_deps():
    """Install the plugin's Python dependencies for the Python Vim embeds.

    Vim links a specific libpython, which is often not the `python3` on PATH,
    so `pip install --user` for the latter doesn't help it. Install into a
    cache directory and hand it to Vim through PYTHONPATH.
    """
    version = _vim_python_version()
    reqs = VIM_REQUIREMENTS.read_bytes()
    target = CACHE_DIR / 'pydeps-py{}'.format(version)
    stamp = target / '.requirements-sha1'
    digest = hashlib.sha1(reqs).hexdigest()
    if not (stamp.exists() and stamp.read_text() == digest):
        python = shutil.which('python' + version)
        if not python:
            pytest.exit('Vim embeds Python {0}, but python{0} is not on PATH to install '
                        'its dependencies'.format(version), returncode=4)
        shutil.rmtree(target, ignore_errors=True)
        subprocess.run([python, '-m', 'pip', 'install', '--quiet', '--disable-pip-version-check',
                        '--target', str(target), '-r', str(VIM_REQUIREMENTS)], check=True)
        stamp.write_text(digest)
    return target


def _base_env(home):
    env = {k: v for k, v in os.environ.items() if not k.startswith('PYTHON')}
    env.update(HOME=str(home), PYTHONDONTWRITEBYTECODE='1', TERM='dumb')
    # The plugin must reach the local fake server directly.
    env['NO_PROXY'] = env['no_proxy'] = ','.join(
        filter(None, [os.environ.get('NO_PROXY', ''), '127.0.0.1', 'localhost']))
    return env


@pytest.fixture
def vim_env(tmp_path, vim_python_deps):
    """Environment for Vim: plugin dependencies installed, no user config."""
    env = _base_env(tmp_path / 'home')
    env['PYTHONPATH'] = str(vim_python_deps)
    return env


@pytest.fixture
def bare_vim_env(tmp_path):
    """Environment for Vim with nothing installed beyond what the plugin ships."""
    return _base_env(tmp_path / 'home')


# ---- LeetCode (fake or real) -------------------------------------------------

class LeetCodeTarget:
    """What the tests run against: the replay server or the live site via proxy."""

    def __init__(self, mode, server, cookies, allow_submit):
        self.mode = mode
        self.server = server
        self.cookies = cookies
        self.allow_submit = allow_submit

    @property
    def base_url(self):
        return self.server.base_url

    @property
    def live(self):
        return self.mode == 'live'


@pytest.fixture
def lc(request):
    opt = request.config.getoption
    mode = opt('--lc-mode')
    if mode == 'replay':
        server = FakeLeetCode([opt('--lc-fixtures')])
        cookies = dict(REPLAY_COOKIES)
    else:
        session = os.environ.get('LEETCODE_SESSION')
        if not session:
            pytest.skip('live mode needs LEETCODE_SESSION (and ideally LEETCODE_CSRFTOKEN) '
                        'copied from a signed-in browser')
        cookies = {'LEETCODE_SESSION': session}
        if os.environ.get('LEETCODE_CSRFTOKEN'):
            cookies['csrftoken'] = os.environ['LEETCODE_CSRFTOKEN']
        server = FakeLeetCode([], upstream=opt('--lc-upstream'), record_dir=opt('--lc-record'))
    server.start()
    yield LeetCodeTarget(mode, server, cookies, opt('--lc-allow-submit'))
    server.stop()


@pytest.fixture
def scenario(tmp_path, lc, vim_env):
    """Factory for a Vim scenario wired to the target under test."""
    counter = [0]

    def make(env=None):
        counter[0] += 1
        return Scenario(tmp_path / 'vim{}'.format(counter[0]), lc.base_url, env or vim_env)

    return make
