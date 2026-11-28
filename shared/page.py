"""page.py: the one way a builder writes a page from its HTML shell.

Load it by path, as gh.py says, from the real file, so a linked skill finds
the shared core:

    spec = importlib.util.spec_from_file_location("page", <path to page.py>)
    page = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(page)

fill(shell, data): the shell with `const DATA = {};` set to the data.
write(output, html): writes the page and prints `page: <output>`.
"""
import json
import os


def fill(shell, data):
    # A `<` inside the data could close the page's <script> tag, so each one is escaped.
    payload = json.dumps(data, ensure_ascii=False).replace("<", r"\u003c")
    return shell.replace("const DATA = {};", "const DATA = " + payload + ";")


def write(output, html):
    # A temp file then a rename, so a failed write keeps the old page.
    tmp = output + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(html)
        os.replace(tmp, output)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print(f"page: {output}")
