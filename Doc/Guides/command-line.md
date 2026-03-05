Command-line usage
===============================================================================

Mud can be used from the command line to open Markdown files in the GUI, or to
render Markdown to HTML on stdout.

How it works depends on which version of Mud you have.


## App Store release

The App Store release of Mud is sandboxed, so it cannot install a CLI tool into
a system directory. Instead, you can add a shell alias to your shell
configuration file.

Add this line to your `~/.zshrc` or `~/.bashrc`:

```sh
alias mud='open -a "/Applications/Mud.app"'
```

Then open a new terminal window (or run `source ~/.zshrc`) for the alias to
take effect.

This alias lets you open files in Mud from the terminal:

```sh
mud README.md
mud ~/notes/*.md
```

**Limitations of the alias approach:**

- It cannot render Markdown to HTML on stdout (no `-u`, `-d`, or `-f` flags).
- It cannot read from stdin.
- It opens files in the Mud GUI; it does not produce terminal output.

For full command-line rendering capability, see the direct release below.


## Direct release

The direct release of Mud (downloaded from
[https://apps.josephpearson.org/mud](https://apps.josephpearson.org/mud))
includes a useful `mud` CLI tool.


After installing this version of Mud, open **Settings → Command Line** and
click **Install**. This creates a symlink in a directory of your choice
(e.g. `/usr/local/bin`).

Once installed, `mud` opens Markdown files in the GUI — or renders them to HTML
when rendering flags are given.

> Tip: If you previously used the App Store release and added a `mud` alias to
> your shell config, remove it. Shell aliases take precedence over PATH
> entries, so the alias would shadow the newly installed symlink.


### Rendering flags

| Flag           | Description                                     |
| -------------- | ----------------------------------------------- |
| `-u`           | Render to full Up mode HTML document (stdout)   |
| `-d`           | Render to full Down mode HTML document (stdout) |
| `-f`           | Render to HTML fragment (no `<html>` wrapper)   |
| `--theme NAME` | Theme: austere, blues, earthy (default), riot   |

Rendering flags read from stdin if no file path is given:

```sh
cat README.md | mud -u > output.html
mud -u README.md > output.html
mud -f README.md
```

Without rendering flags, `mud` opens files in the Mud GUI:

```sh
mud README.md
mud ~/notes/*.md
```


### Browser output

Add `-b` (or `--browser`) to open the rendered output in your default browser
instead of writing to stdout:

```sh
mud -u -b README.md
mud -d -b README.md
cat README.md | mud -u -b
```

With `-u -b`, local images are embedded as data URIs, so the file renders
correctly in the browser even if it references images by relative path.

You can pass multiple files — each opens in its own browser tab:

```sh
mud -u -b chapter-1.md chapter-2.md chapter-3.md
```
