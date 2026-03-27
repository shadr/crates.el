# crates.el

[![License](https://img.shields.io/badge/license-GPL--3.0+-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)

A minor mode for Emacs that displays the latest available version of Rust crates as virtual text in `Cargo.toml` files.

## Installation

### Manual Installation

Clone the repository and add to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/crates.el")
(require 'crates)

(add-hook 'find-file-hook (lambda () (when (string= (file-name-nondirectory buffer-file-name) "Cargo.toml") (crates-mode))))
```

### Doom Emacs

Add to your `packages.el`

``` elisp
(package! crates :recipe (:host github :repo "shadr/crates.el"))
```

Add in your config.el

``` elisp
(use-package! crates
  :config
  (add-hook! 'find-file-hook (when (string= (file-name-nondirectory buffer-file-name) "Cargo.toml") (crates-mode))))
```

Note: when testing I couldn't always attach to the find-file-hook, solution was to switch to `conf-toml-mode-hook` or `toml-ts-mode-hook`

### Using straight.el

```elisp
(straight-use-package
 '(crates :type git :host github :repo "shadr/crates.el"))
```

### Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

This package is licensed under the GNU General Public License v3.0 or later. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [crates.nvim](https://github.com/Saecki/crates.nvim) for Neovim
