#!/usr/bin/env python3
"""Generate the wiki's API reference from the addon's GDScript doc comments.

Godot itself does the parsing: `--doctool --gdscript-docs` walks the source and writes one
class-reference XML per script, the same format the engine uses for its own documentation.
This script turns those into a single Markdown page for the GitHub wiki, translating Godot's
BBCode into Markdown and linking engine types back to the official class reference.

    python3 tools/generate_docs.py --out API-Reference.md

Members, methods, signals and constants whose names start with an underscore are private by
convention and left out, as are undocumented constants (the `preload` consts are not API).

Stdlib only, like tools/publish_to_asset_library.py, so CI needs nothing but Godot.
"""

import argparse
import html
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GODOT_CLASS_URL = "https://docs.godotengine.org/en/stable/classes/class_{}.html"
BANNER = (
    "<!-- Generated from the doc comments in {source} by tools/generate_docs.py.\n"
    "     Edit the doc comments, not this page: it is overwritten on every release. -->"
)


def run_godot(godot, args):
    result = subprocess.run(
        [godot, "--headless", "--path", str(PROJECT_ROOT)] + args,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit("godot failed:\n%s\n%s" % (result.stdout, result.stderr))
    return result.stdout


def dump_class_reference(godot, source, out_dir):
    """Ask Godot for one XML per documented script under `source`."""
    run_godot(godot, ["--doctool", str(out_dir), "--gdscript-docs", source, "--no-docbase"])
    return sorted(Path(out_dir).glob("*.xml"))


def engine_class_names(godot):
    """The real ClassDB list, so a [Type] is only linked when the type actually exists.

    Variant types (Dictionary, Callable, Color...) are not in ClassDB but do have class pages,
    so type_string() supplies them.
    """
    script = Path(tempfile.mkdtemp()) / "_class_list.gd"
    script.write_text(
        "extends SceneTree\n"
        "func _init():\n"
        "\tfor c in ClassDB.get_class_list():\n"
        "\t\tprint(c)\n"
        "\tfor t in range(TYPE_MAX):\n"
        "\t\tprint(type_string(t))\n"
        "\tquit()\n"
    )
    output = run_godot(godot, ["-s", str(script)])
    return {line.strip() for line in output.splitlines() if line.strip().isidentifier()}


class ClassDoc:
    def __init__(self, element):
        # Godot names a script class by its path, quotes included: "addons/foo/Bar.gd".
        self.name = Path(element.get("name").strip('"')).stem
        self.inherits = element.get("inherits", "")
        self.brief = text_of(element.find("brief_description"))
        self.description = text_of(element.find("description"))
        self.tutorials = [
            (link.get("title") or link.text.strip(), link.text.strip())
            for link in element.findall("tutorials/link")
        ]
        self.signals = [e for e in element.findall("signals/signal") if is_public(e)]
        self.constants = [
            e
            for e in element.findall("constants/constant")
            if is_public(e) and (e.text or "").strip()
        ]
        self.members = [e for e in element.findall("members/member") if is_public(e)]
        self.methods = [e for e in element.findall("methods/method") if is_public(e)]

    @property
    def is_documented(self):
        return bool(self.brief or self.description)

    def symbols(self):
        groups = (self.signals, self.constants, self.members, self.methods)
        return {element.get("name") for group in groups for element in group}


def is_public(element):
    return not element.get("name", "").startswith("_")


def text_of(element):
    if element is None or not element.text:
        return ""
    # The XML indents with tabs; code examples indent with spaces, so only tabs are noise.
    return re.sub(r"^\t+", "", element.text.strip("\n"), flags=re.MULTILINE).strip()


def anchor(name):
    return "#" + re.sub(r"[^a-z0-9_-]", "", name.lower().replace(" ", "-"))


def godot_url(class_name, kind=None, member=None):
    """Deep link into the official class reference, matching its anchor scheme."""
    url = GODOT_CLASS_URL.format(class_name.lower())
    if kind == "enum":
        return "%s#enum-%s-%s" % (url, class_name.lower(), member.lower().replace("_", "-"))
    if kind:
        section = "property" if kind == "member" else kind
        return "%s#class-%s-%s-%s" % (
            url,
            class_name.lower(),
            section,
            member.lower().replace("_", "-"),
        )
    return url


def signature(method):
    params = []
    for param in method.findall("param"):
        rendered = "%s: %s" % (param.get("name"), param.get("type"))
        if param.get("default") is not None:
            rendered += " = %s" % param.get("default")
        params.append(rendered)
    returns = method.find("return")
    return "%s(%s) -> %s" % (
        method.get("name"),
        ", ".join(params),
        returns.get("type") if returns is not None else "void",
    )


class BBCode:
    """Godot's documentation markup, rendered as Markdown."""

    def __init__(self, local_symbols, engine_classes):
        self.local_symbols = local_symbols
        self.engine_classes = engine_classes

    def render(self, text):
        # Code blocks are verbatim, so convert only the prose between them.
        parts = re.split(r"\[codeblocks?(?:\s+[^\]]*)?\](.*?)\[/codeblocks?\]", text, flags=re.S)
        out = []
        for index, part in enumerate(parts):
            if index % 2:
                out.append("\n```gdscript\n%s\n```\n" % part.strip("\n"))
            else:
                out.append(self._prose(part))
        return "".join(out).strip()

    def _prose(self, text):
        text = re.sub(r"\[code(?:\s+[^\]]*)?\](.*?)\[/code\]", r"`\1`", text, flags=re.S)
        text = re.sub(r"\[b\](.*?)\[/b\]", r"**\1**", text, flags=re.S)
        text = re.sub(r"\[i\](.*?)\[/i\]", r"*\1*", text, flags=re.S)
        text = re.sub(r"\[url=([^\]]+)\](.*?)\[/url\]", r"[\2](\1)", text, flags=re.S)
        text = re.sub(r"\[(?:param|constant)\s+([^\]]+)\]", r"`\1`", text)
        text = re.sub(r"\[(method|member|signal|enum)\s+([^\]]+)\]", self._reference, text)
        text = re.sub(r"\[([A-Z][A-Za-z0-9]*)\]", self._type_reference, text)
        # Godot writes a paragraph break ([br][br]) as a newline and leaves single [br]s alone.
        text = "\n".join(line.rstrip() for line in text.split("\n"))
        text = text.replace("\n", "\n\n").replace("[br]", "  \n")
        return text

    def _reference(self, match):
        kind, target = match.group(1), match.group(2)
        owner, _, name = target.rpartition(".")
        if not owner and name in self.local_symbols:
            return "[`%s`](%s)" % (name, anchor(name))
        if owner in self.engine_classes:
            return "[`%s.%s`](%s)" % (owner, name, godot_url(owner, kind, name))
        return "`%s`" % target

    def _type_reference(self, match):
        name = match.group(1)
        if name in self.local_symbols:
            return "[`%s`](%s)" % (name, anchor(name))
        if name in self.engine_classes:
            return "[`%s`](%s)" % (name, godot_url(name))
        return "`%s`" % name


def render_class(doc, bbcode, heading):
    lines = ["%s %s" % ("#" * heading, doc.name), ""]
    if doc.inherits:
        inherited = doc.inherits
        if inherited in bbcode.engine_classes:
            inherited = "[`%s`](%s)" % (inherited, godot_url(inherited))
        else:
            inherited = "`%s`" % inherited
        lines += ["*Inherits %s.*" % inherited, ""]
    if doc.brief:
        lines += [bbcode.render(doc.brief), ""]
    if doc.description:
        lines += [bbcode.render(doc.description), ""]
    for title, url in doc.tutorials:
        lines += ["> [%s](%s)" % (title, url), ""]

    sub = "#" * (heading + 1)
    entry = "#" * (heading + 2)

    if doc.methods:
        lines += ["%s Methods" % sub, ""]
        for method in doc.methods:
            lines += ["%s %s" % (entry, method.get("name")), ""]
            lines += ["```gdscript", signature(method), "```", ""]
            body = bbcode.render(text_of(method.find("description")))
            if body:
                lines += [body, ""]

    if doc.members:
        lines += ["%s Properties" % sub, ""]
        for member in doc.members:
            lines += ["%s %s" % (entry, member.get("name")), ""]
            declaration = "%s: %s" % (member.get("name"), member.get("type"))
            default = member.get("default")
            if default and default != "<unknown>":
                declaration += " = %s" % default
            lines += ["```gdscript", declaration, "```", ""]
            body = bbcode.render(text_of(member))
            if body:
                lines += [body, ""]

    if doc.signals:
        lines += ["%s Signals" % sub, ""]
        for element in doc.signals:
            params = ", ".join(
                "%s: %s" % (p.get("name"), p.get("type")) for p in element.findall("param")
            )
            lines += ["%s %s" % (entry, element.get("name")), ""]
            lines += ["```gdscript", "%s(%s)" % (element.get("name"), params), "```", ""]
            body = bbcode.render(text_of(element.find("description")))
            if body:
                lines += [body, ""]

    if doc.constants:
        lines += ["%s Constants" % sub, ""]
        for constant in doc.constants:
            value = html.unescape(constant.get("value", ""))
            declaration = constant.get("name")
            if value and not value.startswith("<"):
                declaration += " = %s" % value
            lines += ["%s %s" % (entry, constant.get("name")), ""]
            lines += ["```gdscript", declaration, "```", ""]
            body = bbcode.render(text_of(constant))
            if body:
                lines += [body, ""]

    return lines


def table_of_contents(docs):
    lines = ["## Contents", ""]
    for doc in docs:
        lines.append("- [%s](%s)" % (doc.name, anchor(doc.name)))
        for label, group in (
            ("Method", doc.methods),
            ("Property", doc.members),
            ("Signal", doc.signals),
            ("Constant", doc.constants),
        ):
            for element in group:
                name = element.get("name")
                lines.append("  - [`%s`](%s) — %s" % (name, anchor(name), label))
    lines.append("")
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot 4 binary (default: godot)")
    parser.add_argument(
        "--source",
        default="res://addons/scene_manager",
        help="directory Godot scans for doc comments",
    )
    parser.add_argument("--out", help="file to write (default: stdout)")
    parser.add_argument("--title", default="API Reference", help="page title")
    parser.add_argument(
        "--first",
        default="SceneManager",
        help="class to place first, before the alphabetical rest",
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as xml_dir:
        paths = dump_class_reference(args.godot, args.source, xml_dir)
        docs = [ClassDoc(ElementTree.parse(path).getroot()) for path in paths]
    docs = [doc for doc in docs if doc.is_documented]
    if not docs:
        sys.exit("no documented scripts found under %s" % args.source)
    docs.sort(key=lambda doc: (doc.name != args.first, doc.name))

    local_symbols = set()
    for doc in docs:
        local_symbols |= doc.symbols()
        local_symbols.add(doc.name)
    bbcode = BBCode(local_symbols, engine_class_names(args.godot))

    lines = [BANNER.format(source=args.source), "", "# %s" % args.title, ""]
    lines += table_of_contents(docs)
    for doc in docs:
        lines += render_class(doc, bbcode, heading=2)

    page = "\n".join(lines).rstrip() + "\n"
    page = re.sub(r"\n{3,}", "\n\n", page)
    if args.out:
        Path(args.out).write_text(page)
        print("wrote %s (%d classes)" % (args.out, len(docs)), file=sys.stderr)
    else:
        sys.stdout.write(page)


if __name__ == "__main__":
    main()
