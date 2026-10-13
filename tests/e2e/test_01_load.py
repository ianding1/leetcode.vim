"""Can the plugin be loaded at all?"""

import pytest


def test_loads_with_dependencies_installed(scenario):
    s = scenario().plugin_imports_itself()
    s.step('runtime autoload/leetcode.vim')
    s.capture('inited', "py3eval('leetcode.inited')")
    s.capture('commands', "[exists(':LeetCodeList'), exists(':LeetCodeTest'), "
                          "exists(':LeetCodeSubmit'), exists(':LeetCodeSignIn'), "
                          "exists(':LeetCodeReset')]")
    r = s.run()
    r.assert_ok()
    assert r.vars['inited'] == 1
    assert r.vars['commands'] == [2, 2, 2, 2, 2]


def test_missing_dependencies_are_reported(scenario, bare_vim_env):
    """#81: without requests/bs4, say so and how to fix it; don't crash later."""
    s = scenario(env=bare_vim_env).plugin_imports_itself()
    s.step('runtime autoload/leetcode.vim')
    s.capture('inited', "py3eval('leetcode.inited')")
    s.capture('py', "py3eval('\"%d.%d\" % sys.version_info[:2]')")
    s.step('LeetCodeList')
    s.step('LeetCodeSignIn')
    r = s.run()
    if r.vars.get('inited') == 1:
        pytest.skip('requests and bs4 are importable without PYTHONPATH here')
    r.assert_ok()   # no NameError or E684, just a message
    assert "No module named" in r.output, r.describe()
    assert 'python{} -m pip install --user requests beautifulsoup4'.format(r.vars['py']) \
        in r.output, r.describe()


def test_china_uses_leetcode_cn(scenario):
    s = scenario().plugin_imports_itself().let('leetcode_china', 1)
    s.step('runtime autoload/leetcode.vim')
    s.capture('base', "py3eval('leetcode.LC_BASE')")
    r = s.run()
    r.assert_ok()
    assert r.vars['base'] == 'https://leetcode.cn'
