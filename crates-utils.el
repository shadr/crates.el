;;; crates-utils.el --- Utility functions for crates.el -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr@nixos>
;; Maintainer: shadr <shadr@nixos>
;; Version: 0.0.1
;; Keywords: tools
;; Homepage: https://github.com/shadr/crates.el
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; Utility functions for parsing and comparing version strings.
;;
;;; Code:

(require 'cl-lib)

(cl-defstruct crates--version-string major minor patch)

(defun crates--parse-version-string (str)
  "Parse a version string like \"1.2.3\" into a version structure."
  (let* ((splited (split-string str "\\."))
         (major (nth 0 splited))
         (minor (nth 1 splited))
         (patch (nth 2 splited))
         (major-number (when major (string-to-number major)))
         (minor-number (when minor (string-to-number minor)))
         (patch-number (when patch (string-to-number patch))))
    (make-crates--version-string :major major-number :minor minor-number :patch patch-number)))


(defun crates--version-string-less (vs1 vs2)
  "Return non-nil if VS1 is less than VS2."
  (let ((major1 (or (crates--version-string-major vs1) 0))
        (major2 (or (crates--version-string-major vs2) 0))
        (minor1 (or (crates--version-string-minor vs1) 0))
        (minor2 (or (crates--version-string-minor vs2) 0))
        (patch1 (or (crates--version-string-patch vs1) 0))
        (patch2 (or (crates--version-string-patch vs2) 0)))
    (or (< major1 major2)
        (and (= major1 major2)
             (or (< minor1 minor2)
                 (and (= minor1 minor2)
                      (< patch1 patch2)))))))

(defun crates--version-string-greater (vs1 vs2)
  "Return non-nil if VS1 is greater than VS2."
  (crates--version-string-less vs2 vs1))

(defun crates--version-string-to-string (vs)
  "Convert a version structure VS to a string."
  (format "%i.%i.%i"
          (or (crates--version-string-major vs) 0)
          (or (crates--version-string-minor vs) 0)
          (or (crates--version-string-patch vs) 0)))

(provide 'crates-utils)
;;; crates-utils.el ends here
