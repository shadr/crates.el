;;; cargo-toml-mode-utils.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr@nixos>
;; Maintainer: shadr <shadr@nixos>
;; Created: марта 27, 2026
;; Modified: марта 27, 2026
;; Version: 0.0.1
;; Keywords: abbrev bib c calendar comm convenience data docs emulations extensions faces files frames games hardware help hypermedia i18n internal languages lisp local maint mail matching mouse multimedia news outlines processes terminals tex text tools unix vc
;; Homepage: https://github.com/shadr.nn@gmail.com/cargo-toml-mode-utils
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

(cl-defstruct version-string major minor patch)

(defun cargo-toml--parse-version-string (str)
  (let* ((splited (split-string str "\\."))
         (major (nth 0 splited))
         (minor (nth 1 splited))
         (patch (nth 2 splited))
         (major-number (when major (string-to-number major)))
         (minor-number (when minor (string-to-number minor)))
         (patch-number (when patch (string-to-number patch))))
    (make-version-string :major major-number :minor minor-number :patch patch-number)))


(defun version-string-less (vs1 vs2)
  (let ((major1 (or (version-string-major vs1) 0))
        (major2 (or (version-string-major vs2) 0))
        (minor1 (or (version-string-minor vs1) 0))
        (minor2 (or (version-string-minor vs2) 0))
        (patch1 (or (version-string-patch vs1) 0))
        (patch2 (or (version-string-patch vs2) 0)))
    (or (< major1 major2)
        (and (= major1 major2)
             (or (< minor1 minor2)
                 (and (= minor1 minor2)
                      (< patch1 patch2)))))))

(defun version-string-greater (vs1 vs2)
  (version-string-less vs2 vs1))

(defun version-string-to-string (vs)
  (format "%i.%i.%i"
          (or (version-string-major vs) 0)
          (or (version-string-minor vs) 0)
          (or (version-string-patch vs) 0)))

(provide 'cargo-toml-mode-utils)
;;; cargo-toml-mode-utils.el ends here
