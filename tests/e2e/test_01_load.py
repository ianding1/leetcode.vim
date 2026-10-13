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


@pytest.mark.xfail(strict=True, reason='#81: vendored urllib3 1.25 cannot be imported on '
                                       'Python >= 3.12, and the failure is silent')
def test_loads_with_only_vendored_dependencies(scenario, bare_vim_env):
    """Users who never pip-installed requests fall back to autoload/thirdparty."""
    s = scenario(env=bare_vim_env).plugin_imports_itself()
    s.step('runtime autoload/leetcode.vim')
    s.capture('inited', "py3eval('leetcode.inited')")
    r = s.run()
    r.assert_ok()
    assert r.vars['inited'] == 1, r.describe()


@pytest.mark.xfail(strict=True, reason='a failed import is not reported when the plugin '
                                       'loads; users only see a NameError later (#81)')
def test_missing_dependencies_are_reported_on_load(scenario, bare_vim_env):
    s = scenario(env=bare_vim_env).plugin_imports_itself()
    s.step('runtime autoload/leetcode.vim')
    s.capture('inited', "py3eval('leetcode.inited')")
    r = s.run()
    if r.vars.get('inited') == 1:
        pytest.skip('dependencies imported fine; nothing to report')
    assert 'requests' in r.output or 'pip' in r.output, r.describe()
