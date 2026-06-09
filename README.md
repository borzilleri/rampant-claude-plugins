# Usage

Clone the repository:

```bash
git clone https://github.com/borzilleri/rampant-claude-plugins.git
```

Add the marketplace to claude code:

```bash
claude plugin marketplace add /path/to/rampant-claude-plugins
```

Install Plugins

```bash
claude plugin install bug-hunt@rampant-io-plugins
```


# Plugin List

## bug-hunt

Bug finding capabilities.

* Agents: `bug-hunter`, `bug-skeptic`, `bug-referree` to find and validate bugs in your code.
* Skills: `bug-hunt`, a framework for finding and validating bugs as real that Claude uses when analysing code for bugs or defects.

## command-protection

Pre-Tool-Use hooks to guard against destructive actions. Combine this with a more permissive permission structure in your settings.json, e.g.:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(//Users/<username>/**)",
      "Read(//private/tmp/**)",
    ]
  }
}
```

* Hooks: `check-dangerous-command.sh` and `check-sensitive-file.sh` guard against running destructive/dangerous commands, or accessing sensitive files.


## software-dev

Toolkit for software development

* Agent: `open-source-librarian` provides expertise on open source libraries on GitHub
* Agent: `software-architect` provides expertise on software architecture/
* Agent: `tech-docs-writer` provides expertise and guidelines for technical documentation writing.
* Hook: `warn-protected-branch.sh` prints a warning when editing on a protected branch (main, master, etc).