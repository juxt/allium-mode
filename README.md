# allium-mode

Emacs major mode for the [Allium](https://github.com/juxt/allium-tools) specification language.

**Compatibility:** Allium Tools core 2.x

## Installation

### Using straight.el

```elisp
(use-package allium-mode
  :straight (:host github :repo "juxt/allium-mode")
  :mode "\.allium'")
```

### Using Doom Emacs

In `packages.el`:

```elisp
(package! allium-mode
  :recipe (:host github :repo "juxt/allium-mode"))
```

In `config.el`:

```elisp
(use-package! allium-mode
  :mode "\.allium'")
```

### Manual installation

1. Clone this repository.
2. Add the directory to your `load-path`.
3. Add `(require 'allium-mode)` to your configuration.

## Features

- Syntax highlighting (regex-based or tree-sitter).
- Indentation support.
- LSP integration via `eglot` or `lsp-mode`.
- Tree-sitter support for Emacs 29+.

## Usage

`allium-mode` uses standard Emacs LSP/Xref commands rather than adding custom commands.

After opening an `.allium` file and connecting LSP (`eglot-ensure` or
`lsp-deferred`), you can use:

- Hover: `M-x eldoc` (or automatic ElDoc display)
- Go to definition: `M-.` (`xref-find-definitions`)
- Find references: `M-?` (`xref-find-references`)
- Rename symbol: `M-x eglot-rename` or `M-x lsp-rename`
- Code actions: `M-x eglot-code-actions` or `M-x lsp-execute-code-action`
- Format buffer: `M-x eglot-format-buffer` or `M-x lsp-format-buffer`
- Outline navigation: `M-x imenu` (with richer structure in `allium-ts-mode`)

Built-in mode commands and variables:

- Switch modes: `M-x allium-mode` / `M-x allium-ts-mode`
- Indentation width: customise `allium-indent-offset`
- LSP server command: customise `allium-lsp-server-command`

## LSP configuration

### eglot

```elisp
(add-hook 'allium-mode-hook 'eglot-ensure)
```

### lsp-mode

```elisp
(add-hook 'allium-mode-hook 'lsp-deferred)
```

## Testing

Run the ERT suite:

```bash
./scripts/run-tests.sh
```

This runs Emacs in `-Q --batch` mode against deterministic unit tests for core major mode behaviour, `eglot` registration and `lsp-mode` client registration.

## Licence

[MIT](LICENSE)
