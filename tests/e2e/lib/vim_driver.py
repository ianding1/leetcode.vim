"""Run a scenario in a real, headless Vim or Neovim with the plugin loaded."""

import json
import re
import subprocess
from pathlib import Path

LIB_DIR = Path(__file__).resolve().parent
REPO_ROOT = LIB_DIR.parents[2]


def _vim_str(s):
    """Quote `s` as a single-quoted Vim string literal."""
    return "'" + s.replace("'", "''") + "'"


class VimResult:
    def __init__(self, data, script_path, returncode):
        self.steps = data.get('steps', [])
        self.vars = data.get('vars', {})
        self.buffers = data.get('buffers', {})
        self.messages = data.get('messages', [])
        self.current_buffer = data.get('current_buffer')
        self.script_path = script_path
        self.returncode = returncode

    @property
    def errors(self):
        errs = [s for s in self.steps if s['error']]
        if 'bootstrap_error' in self.vars:
            errs.insert(0, {'cmd': 'bootstrap', 'error': self.vars['bootstrap_error']})
        return errs

    @property
    def output(self):
        """Everything the steps echoed, plus :messages."""
        echoed = [line for s in self.steps for line in s.get('output', '').split('\n')]
        return '\n'.join(line for line in echoed + self.messages if line.strip())

    def buffer(self, pattern):
        """Lines of the first loaded buffer whose name matches `pattern`."""
        for name, lines in self.buffers.items():
            if re.search(pattern, name):
                return lines
        return None

    def text(self, pattern):
        lines = self.buffer(pattern)
        return None if lines is None else '\n'.join(lines)

    def describe(self):
        """Human-readable dump used in assertion messages."""
        out = ['script: {}'.format(self.script_path)]
        out.append('errors:')
        out += ['  {cmd}: {error}'.format(**e) for e in self.errors] or ['  (none)']
        out.append('output and messages:')
        out += ['  ' + m for m in self.output.split('\n') if m.strip()] or ['  (none)']
        out.append('buffers: ' + ', '.join(repr(b) for b in self.buffers))
        return '\n'.join(out)

    def assert_ok(self):
        assert not self.errors, 'Vim reported errors\n' + self.describe()


class Scenario:
    """Builds a Vim script step by step, then runs it."""

    def __init__(self, workdir, base_url, env, timeout=60, editor='vim', host_python=None,
                 backend='python'):
        self.workdir = Path(workdir)
        self.editor = editor
        self.host_python = host_python
        self.backend = backend
        self.base_url = base_url
        self.saved_cookies = None
        self.env = env
        self.timeout = timeout
        self.config = {
            'base_url': base_url,
            'autoload_dir': str(REPO_ROOT / 'autoload'),
            'browser_cookies': None,
        }
        self.options = {
            'leetcode_solution_filetype': 'cpp',
            'leetcode_browser': 'paste',
            'leetcode_base_url': base_url,
            'leetcode_cookie_file': str(self.workdir / 'cookies.json'),
            'leetcode_backend': backend,
        }
        self.lines = []

    # ---- configuration ---------------------------------------------------

    def signed_in(self, cookies):
        """Start with these cookies saved, as if pasted at an earlier sign-in."""
        self.saved_cookies = dict(cookies)
        return self

    def browser_has(self, cookies, browser='chrome'):
        """Let the real sign-in path find these cookies in a fake browser."""
        self.config['browser_cookies'] = dict(cookies)
        self.options['leetcode_browser'] = browser
        return self

    def let(self, name, value):
        self.options[name] = value
        return self

    def unlet(self, name):
        """Leave g:<name> unset, so the plugin's default applies."""
        self.options.pop(name, None)
        return self

    # ---- steps -----------------------------------------------------------

    def step(self, cmd):
        self.lines.append('call E2EStep({})'.format(_vim_str(cmd)))
        return self

    def type_ahead(self, keys):
        """Queue keys for the next prompt (input(), inputsecret(), ...).

        Headless editors can't answer a prompt with no keys queued: Vim exits
        and Neovim waits forever.
        """
        return self.step('call feedkeys("' + keys.replace('"', '\\"') + '", "t")')

    def press(self, keys):
        """Type normal-mode keys, e.g. press('\\<CR>'). Buffer maps apply."""
        return self.step('execute "normal ' + keys.replace('"', '\\"') + '"')

    def goto(self, pattern):
        """Move the cursor to the first line matching `pattern`."""
        return self.step('if search({}, "cw") == 0 | throw "e2e: pattern not found: " . {} | endif'
                         .format(_vim_str(pattern), _vim_str(pattern)))

    def wait_for(self, expr, timeout_ms=15000):
        self.lines.append('call E2EWaitFor({}, {})'.format(_vim_str(expr), timeout_ms))
        return self

    def wait_for_buffer(self, pattern, timeout_ms=15000):
        return self.wait_for('E2EBufferLoaded({})'.format(_vim_str(pattern)), timeout_ms)

    def capture(self, name, expr):
        self.lines.append('call E2ECapture({}, {})'.format(_vim_str(name), _vim_str(expr)))
        return self

    def raw(self, line):
        self.lines.append(line)
        return self

    # ---- run -------------------------------------------------------------

    def run(self, name='scenario'):
        self.workdir.mkdir(parents=True, exist_ok=True)
        config_path = self.workdir / (name + '.config.json')
        out_path = self.workdir / (name + '.result.json')
        script_path = self.workdir / (name + '.vim')
        config_path.write_text(json.dumps(self.config), 'utf-8')
        if self.saved_cookies is not None:
            host = self.base_url.split('://', 1)[1].split('/')[0]
            Path(self.options['leetcode_cookie_file']).write_text(
                json.dumps({host: self.saved_cookies}), 'utf-8')
        if out_path.exists():
            out_path.unlink()

        script = [
            'set nocompatible',
            'set columns=200 lines=60 shortmess+=F nomore',
            'let g:e2e_out = {}'.format(_vim_str(str(out_path))),
            'let g:e2e_config = {}'.format(_vim_str(str(config_path))),
            'source {}'.format(LIB_DIR / 'harness.vim'),
        ]
        if self.editor == 'nvim':
            script.append('let g:python3_host_prog = {}'.format(_vim_str(self.host_python)))
        for k, v in self.options.items():
            script.append('let g:{} = {}'.format(k, _vim_str(v) if isinstance(v, str) else v))
        if self.config['browser_cookies'] is not None:
            script.append('py3file {}'.format(LIB_DIR / 'bootstrap.py'))
        script += [
            'set runtimepath^={}'.format(REPO_ROOT),
            'runtime plugin/leetcode.vim',
        ]
        script += self.lines
        script.append('call E2EFinish()')
        script_path.write_text('\n'.join(script) + '\n', 'utf-8')

        if self.editor == 'nvim':
            cmd = ['nvim', '--headless', '-u', 'NONE', '-i', 'NONE', '-n',
                   '-S', str(script_path)]
        else:
            cmd = ['vim', '-N', '-u', 'NONE', '-i', 'NONE', '-n', '--not-a-term',
                   '-S', str(script_path)]
        try:
            proc = subprocess.run(cmd, cwd=str(self.workdir), env=self.env,
                                  stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.PIPE, timeout=self.timeout)
            returncode = proc.returncode
        except subprocess.TimeoutExpired:
            raise AssertionError('{} did not finish within {}s; script: {}'
                                 .format(self.editor, self.timeout, script_path))

        if not out_path.exists():
            raise AssertionError('{} exited ({}) without writing a result; script: {}\n{}'
                                 .format(self.editor, returncode, script_path,
                                         proc.stderr.decode('utf-8', 'replace')[-2000:]))
        data = json.loads(out_path.read_text('utf-8'))
        return VimResult(data, script_path, returncode)
