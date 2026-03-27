;;; test-utils.el --- Description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr@nixos>
;; Maintainer: shadr <shadr@nixos>
;; Created: марта 27, 2026
;; Modified: марта 27, 2026
;; Version: 0.0.1
;; Keywords: abbrev bib c calendar comm convenience data docs emulations extensions faces files frames games hardware help hypermedia i18n internal languages lisp local maint mail matching mouse multimedia news outlines processes terminals tex text tools unix vc
;; Homepage: https://github.com/shadr.nn@gmail.com/test-utils
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Description
;;
;;; Code:

(require 'buttercup)
(require 'cargo-toml-mode-utils)

(describe "Version string parses from "
  (it "a full version string correctly"
    (let ((vs (cargo-toml--parse-version-string "1.2.3")))
      (expect (version-string-major vs) :to-equal 1)
      (expect (version-string-minor vs) :to-equal 2)
      (expect (version-string-patch vs) :to-equal 3)))
  (it "a two element version string correctly"
    (let ((vs (cargo-toml--parse-version-string "1.2")))
      (expect (version-string-major vs) :to-equal 1)
      (expect (version-string-minor vs) :to-equal 2)
      (expect (version-string-patch vs) :to-equal nil)))
  (it "a single element version string correctly"
    (let ((vs (cargo-toml--parse-version-string "1")))
      (expect (version-string-major vs) :to-equal 1)
      (expect (version-string-minor vs) :to-equal nil)
      (expect (version-string-patch vs) :to-equal nil))))

(describe "Version string comparison"
  (cl-flet ((test-less (vs1 vs2)
              (version-string-less
               (cargo-toml--parse-version-string vs1)
               (cargo-toml--parse-version-string vs2))))
    (it "major version 1 less than 2"
      (test-less "1.0.0" "2.0.0") :to-be t)
    (it "major version 2 is not less than 2"
      (test-less "2.0.0" "1.0.0") :to-be nil)
    (it "minor version 1 is less than 2"
      (test-less "1.1.0" "1.2.0") :to-be t)
    (it "minor version 2 is not less than 1"
      (test-less "1.2.0" "1.1.0") :to-be t)
    (it "patch version 1 is less than 2"
      (test-less "1.0.1" "1.0.2") :to-be t)
    (it "patch version 2 is not less than 1"
      (test-less "1.0.2" "1.0.1") :to-be t)))


(provide 'test-utils)
;;; test-utils.el ends here
