;;; test-crates-utils.el --- Tests for crates-utils.el -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr.nn@gmail.com>
;; Maintainer: shadr <shadr.nn@gmail.com>
;; Version: 0.0.1
;; Keywords: tools
;; Homepage: https://github.com/shadr/crates.el
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; Tests for version string parsing and comparison functions.
;;
;;; Code:

(require 'buttercup)
(require 'crates-utils)

(describe "Version string parses from "
  (it "a full version string correctly"
    (let ((vs (crates--parse-version-string "1.2.3")))
      (expect (crates--version-string-major vs) :to-equal 1)
      (expect (crates--version-string-minor vs) :to-equal 2)
      (expect (crates--version-string-patch vs) :to-equal 3)))
  (it "a two element version string correctly"
    (let ((vs (crates--parse-version-string "1.2")))
      (expect (crates--version-string-major vs) :to-equal 1)
      (expect (crates--version-string-minor vs) :to-equal 2)
      (expect (crates--version-string-patch vs) :to-equal nil)))
  (it "a single element version string correctly"
    (let ((vs (crates--parse-version-string "1")))
      (expect (crates--version-string-major vs) :to-equal 1)
      (expect (crates--version-string-minor vs) :to-equal nil)
      (expect (crates--version-string-patch vs) :to-equal nil))))

(describe "Version string comparison"
  (cl-flet ((test-less (vs1 vs2)
              (crates--version-string-less
               (crates--parse-version-string vs1)
               (crates--parse-version-string vs2))))
    (it "major version 1 less than 2"
      (test-less "1.0.0" "2.0.0") :to-be t)
    (it "major version 2 is not less than 2"
      (test-less "2.0.0" "1.0.0") :to-be nil)
    (it "minor version 1 is less than 2"
      (test-less "1.1.0" "1.2.0") :to-be t)
    (it "minor version 2 is not less than 1"
      (test-less "1.2.0" "1.1.0") :to-be nil)
    (it "patch version 1 is less than 2"
      (test-less "1.0.1" "1.0.2") :to-be t)
    (it "patch version 2 is not less than 1"
      (test-less "1.0.2" "1.0.1") :to-be nil)))


(provide 'test-crates-utils)
;;; test-crates-utils.el ends here
