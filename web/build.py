"""Builds web/dist/index.html: one self-contained page (styles, scripts and logo inlined)."""
import base64, json, pathlib
here = pathlib.Path(__file__).parent
src = here / "src"
parser = (src / "parser.js").read_text()
page = (src / "index.template.html").read_text()
parts = {
    "/*__STYLE__*/": (src / "style.css").read_text(),
    "/*__PARSER__*/": parser,
    "/*__ANALYTICS__*/": (src / "analytics.js").read_text(),
    "/*__PARSER_SRC__*/": json.dumps(parser).replace("</", "<\\/"),
    "/*__APP__*/": (src / "app.js").read_text(),
    "__LOGO__": base64.b64encode((src / "be-logo.png").read_bytes()).decode(),
}
for k, v in parts.items():
    assert k in page, k
    page = page.replace(k, v)
assert "</script" not in parser and "</script" not in (src / "app.js").read_text()
out = here / "dist" / "index.html"
out.write_text(page)
print(out, len(page) // 1024, "KB")
