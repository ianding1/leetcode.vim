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
    g.addoption('--lc-editor', choices=['all', 'vim', 'nvim'],
                default=os.environ.get('LEETCODE_E2E_EDITOR', 'all'),
                help='editor(s) to run the plugin in; "all" runs each installed one')
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


# ---- Editors and their Python -----------------------------------------------
#
# Vim embeds a specific libpython, often not the `python3` on PATH, so the
# plugin's dependencies are installed for exactly that version. Neovim runs
# Python in a separate host process (pynvim) using `python3` from PATH, or
# $LEETCODE_E2E_NVIM_PYTHON. Either way the packages go into a cache
# directory handed over through PYTHONPATH, never into your environment.

EDITORS = ('vim', 'nvim')
NVIM_HOST_REQUIREMENTS = b'pynvim>=0.5\n'


def _python_version(python):
    out = subprocess.run([python, '-c', 'import sys; print("%d.%d" % sys.version_info[:2])'],
                         capture_output=True, text=True, check=True)
    return out.stdout.strip()


def _vim_python_version():
    probe = CACHE_DIR / 'vim-python-version'
    CACHE_DIR.mkdir(exist_ok=True)
    if probe.exists():
        probe.unlink()
    subprocess.run(['vim', '-N', '-u', 'NONE', '-i', 'NONE', '-es',
                    '-c', 'py3 import sys; open(r"{}", "w").write("%d.%d" % sys.version_info[:2])'
                    .format(probe),
                    '-c', 'qa!'], stdin=subprocess.DEVNULL, timeout=30)
    if not probe.exists():
        pytest.exit('vim has no working +python3 support', returncode=4)
    return probe.read_text().strip()


def _pip_install(python, name, requirements):
    """Install `requirements` (bytes) for `python` into a cached directory."""
    target = CACHE_DIR / '{}-py{}'.format(name, _python_version(python))
    stamp = target / '.requirements-sha1'
    digest = hashlib.sha1(requirements).hexdigest()
    if not (stamp.exists() and stamp.read_text() == digest):
        shutil.rmtree(target, ignore_errors=True)
        target.mkdir(parents=True)
        reqs_file = target / '.requirements.txt'
        reqs_file.write_bytes(requirements)
        subprocess.run([python, '-m', 'pip', 'install', '--quiet', '--disable-pip-version-check',
                        '--target', str(target), '-r', str(reqs_file)], check=True)
        stamp.write_text(digest)
    return target


def _isolated_python(python):
    """A venv of `python` without its site-packages, so that only what we put
    on PYTHONPATH is importable (and "dependencies missing" can be tested)."""
    venv = CACHE_DIR / 'venv-py{}'.format(_python_version(python))
    exe = venv / 'bin' / 'python'
    if not exe.exists():
        subprocess.run([python, '-m', 'venv', '--without-pip', str(venv)], check=True)
    return str(exe)


class EditorSetup:
    """How to start one editor, and the Python paths it needs."""

    def __init__(self, name, host_python=None, host_path=None, deps_path=None):
        self.name = name
        self.host_python = host_python  # nvim only: g:python3_host_prog
        self.host_path = host_path      # nvim only: pynvim
        self.deps_path = deps_path      # requests, bs4

    def env(self, home, with_deps=True):
        env = {k: v for k, v in os.environ.items() if not k.startswith('PYTHON')}
        env.update(HOME=str(home), PYTHONDONTWRITEBYTECODE='1', PYTHONNOUSERSITE='1',
                   TERM='dumb')
        for xdg in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME'):
            env.pop(xdg, None)
        # The plugin must reach the local fake server directly.
        env['NO_PROXY'] = env['no_proxy'] = ','.join(
            filter(None, [os.environ.get('NO_PROXY', ''), '127.0.0.1', 'localhost']))
        paths = [self.host_path] + ([self.deps_path] if with_deps else [])
        paths = [str(p) for p in paths if p]
        if paths:
            env['PYTHONPATH'] = os.pathsep.join(paths)
        return env


_setups = {}


def _editor_setup(name):
    if name in _setups:
        return _setups[name]
    if not shutil.which(name):
        pytest.skip('{} is not installed'.format(name))
    deps = VIM_REQUIREMENTS.read_bytes()
    if name == 'vim':
        version = _vim_python_version()
        python = shutil.which('python' + version)
        if not python:
            pytest.exit('Vim embeds Python {0}, but python{0} is not on PATH to install '
                        'its dependencies'.format(version), returncode=4)
        setup = EditorSetup('vim', deps_path=_pip_install(python, 'pydeps', deps))
    else:
        python = os.environ.get('LEETCODE_E2E_NVIM_PYTHON') or shutil.which('python3')
        setup = EditorSetup('nvim', host_python=_isolated_python(python),
                            host_path=_pip_install(python, 'nvim-host', NVIM_HOST_REQUIREMENTS),
                            deps_path=_pip_install(python, 'pydeps', deps))
    _setups[name] = setup
    return setup


def pytest_generate_tests(metafunc):
    if 'editor' in metafunc.fixturenames:
        choice = metafunc.config.getoption('--lc-editor')
        editors = EDITORS if choice == 'all' else (choice,)
        metafunc.parametrize('editor', editors, indirect=True)


@pytest.fixture
def editor(request):
    return _editor_setup(request.param)


@pytest.fixture
def vim_env(tmp_path, editor):
    """Environment for the editor: plugin dependencies installed, no user config."""
    return editor.env(tmp_path / 'home')


@pytest.fixture
def bare_vim_env(tmp_path, editor):
    """Environment without the plugin's Python dependencies."""
    return editor.env(tmp_path / 'home', with_deps=False)


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
def scenario(tmp_path, lc, editor, vim_env):
    """Factory for an editor scenario wired to the target under test."""
    counter = [0]

    def make(env=None):
        counter[0] += 1
        return Scenario(tmp_path / '{}{}'.format(editor.name, counter[0]), lc.base_url,
                        env or vim_env, editor=editor.name, host_python=editor.host_python)

    return make
