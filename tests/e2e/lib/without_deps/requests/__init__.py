# Put first on PYTHONPATH for scenarios "without the plugin's Python
# dependencies": the system Python may have requests installed (Ubuntu's
# does, on GitHub's runners), so leaving it out isn't enough.
raise ModuleNotFoundError("No module named 'requests'", name='requests')
