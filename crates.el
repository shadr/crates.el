;;; crates.el --- Minor mode for Cargo.toml with crate version overlays -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr.nn@gmail.com>
;; Maintainer: shadr <shadr.nn@gmail.com>
;; Version: 0.1.0
;; Homepage: https://github.com/shadr/crates.el
;; Package-Requires: ((emacs "24.3"))
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;; A minor mode for editing Cargo.toml files that displays the latest available
;; version of crates as virtual text at the end of the line.
;;
;; Features:
;; - Shows latest crate version from crates.io as virtual text
;; - Async version fetching to avoid blocking
;; - Smart caching: only fetches on first visit or when new dependency is added
;;
;; Usage:
;; Enable with `M-x crates-mode' or add to hook:
;;   (add-hook 'find-file-hook (lambda () (when (string= (file-name-nondirectory buffer-file-name) "Cargo.toml") (crates-mode))))
;;
;;; Code:

(require 'json)
(require 'url)
(require 'subr-x)

(require 'crates-utils)

(defgroup crates nil
  "Minor mode for Cargo.toml files with crate version overlays."
  :group 'tools
  :prefix "crates-")

(defcustom crates-overlay-latest-face 'crates-latest-version
  "Face used to display the latest version overlay."
  :type 'face
  :group 'crates)

(defcustom crates-overlay-outdated-face 'crates-outdated-version
  "Face used to display the outdated version overlay."
  :type 'face
  :group 'crates)

(defcustom crates-fetch-timeout 10
  "Timeout in seconds for fetching crate version information."
  :type 'integer
  :group 'crates)

(defface crates-latest-version
  '((t (:foreground "#505050" :slant italic :height 0.8)))
  "Face for displaying latest crate version."
  :group 'crates)

(defface crates-outdated-version
  '((t (:foreground "#f9e2af" :slant italic :height 0.8)))
  "Face for displaying outdated crate version."
  :group 'crates)

(defvar-local crates--overlays nil
  "List of active version overlays in the current buffer.")

(defvar-local crates--version-cache nil
  "Cache of fetched crate versions for the current buffer.")

(defvar-local crates--pending-requests nil
  "Track pending async requests to avoid duplicates in current buffer.")

(defvar-local crates--visited-dependencies nil
  "Set of dependencies that have already been visited/fetched.")

(defun crates--init-buffers-local-vars ()
  "Initialize buffer-local variables."
  (unless crates--version-cache
    (setq crates--version-cache (make-hash-table :test 'equal)))
  (unless crates--pending-requests
    (setq crates--pending-requests (make-hash-table :test 'equal)))
  (unless crates--visited-dependencies
    (setq crates--visited-dependencies (make-hash-table :test 'equal))))

;;;###autoload
(define-minor-mode crates-mode
  "Minor mode for editing Cargo.toml files.

Displays the latest available version of crates as virtual text
at the end of dependency declaration lines.

Commands:
\\{crates-mode-map}"
  :lighter " Crates"
  (if crates-mode
      (crates--enable)
    (crates--disable)))

(defun crates--enable ()
  "Enable crates-mode."
  (crates--init-buffers-local-vars)
  (crates-refresh-overlays)
  (add-hook 'after-change-functions #'crates--after-change nil t)
  (add-hook 'kill-buffer-hook #'crates--cleanup nil t))

(defun crates--disable ()
  "Disable crates-mode."
  (crates--remove-all-overlays)
  (remove-hook 'after-change-functions #'crates--after-change t)
  (remove-hook 'kill-buffer-hook #'crates--cleanup t))

(defun crates--cleanup ()
  "Clean up overlays and cache when buffer is killed."
  (crates--remove-all-overlays)
  (when crates--version-cache
    (clrhash crates--version-cache))
  (when crates--pending-requests
    (clrhash crates--pending-requests))
  (when crates--visited-dependencies
    (clrhash crates--visited-dependencies))
  (setq crates--version-cache nil)
  (setq crates--pending-requests nil)
  (setq crates--visited-dependencies nil))

(defun crates--remove-all-overlays ()
  "Remove all crates overlays from the current buffer."
  (mapc #'delete-overlay crates--overlays)
  (setq crates--overlays nil))

(defun crates--after-change (_beg _end _len)
  "Handle buffer changes.
_BEG, _END, and _LEN are the change boundaries and length."
  (when crates-mode
    (crates--remove-all-overlays)
    ;; Only refresh overlays for new dependencies, not all
    (crates-refresh-overlays-for-new-dependencies)))

(defvar-local crates--in-dependencies-section nil
  "Track if we're currently in a dependencies section.")

(defun crates--parse-dependency-line ()
  "Parse the current line for a dependency declaration.

Returns a plist with :crate and :version if found, nil otherwise."
  (save-excursion
    (beginning-of-line)
    ;; Check if we're entering/exiting a dependencies section
    (let ((line (thing-at-point 'line t)))
      ;; Track section changes
      (when (string-match "^\\s-*\\[\\(.*dependencies.*\\)\\]" line)
        (setq crates--in-dependencies-section t))
      (when (and (string-match "^\\s-*\\[" line)
                 (not (string-match "^\\[.*dependencies" line)))
        (setq crates--in-dependencies-section nil))
      ;; Only parse if in dependencies section
      (when crates--in-dependencies-section
        (cond
         ;; Simple format: crate = "version"
         ((string-match "^\\s-*\\([a-zA-Z0-9_-]+\\)\\s-*=\\s-*\"\\([^\"]+\\)\"" line)
          (let ((crate (match-string 1 line))
                (version (match-string 2 line)))
            (unless (string-prefix-p "{" version)
              (list :crate crate :version (crates--parse-version-string version)))))
         ;; Table format: crate = { version = "..." }
         ((string-match "^\\s-*\\([a-zA-Z0-9_-]+\\)\\s-*=\\s-*{" line)
          (let ((crate (match-string 1 line)))
            (when (string-match "version\\s-*=\\s-*\"\\([^\"]+\\)\"" line)
              (list :crate crate :version (crates--parse-version-string (match-string 1 line)))))))))))

(defun crates--find-dependencies ()
  "Find all dependency declarations in the buffer.

Returns a list of plists with :crate, :version, and :position."
  (save-excursion
    (goto-char (point-min))
    ;; Reset section tracking
    (setq crates--in-dependencies-section nil)
    (let (dependencies)
      (while (not (eobp))
        (let ((dep (crates--parse-dependency-line)))
          (when dep
            (push (nconc dep (list :position (point))) dependencies)))
        (forward-line 1))
      (nreverse dependencies))))

(defun crates--fetch-latest-version (crate callback)
  "Fetch the latest version of CRATE from crates.io.
CALLBACK is called with the version string or nil on error."
  (let ((cached (gethash crate crates--version-cache))
        (buffer (current-buffer))
        (version-cache crates--version-cache)
        (pending-requests crates--pending-requests))
    (if cached
        (funcall callback cached)
      (let ((url (format "https://crates.io/api/v1/crates/%s" crate)))
        (unless (gethash crate pending-requests)
          (puthash crate t pending-requests)
          (let ((process-environment process-environment))
            (url-retrieve url
                          (lambda (status)
                            (crates--handle-response status crate callback buffer version-cache pending-requests))
                          nil t t)))))))

(defun crates--handle-response (status crate callback buffer version-cache pending-requests)
  "Handle the HTTP response for crate version fetch.
STATUS is the request status, CRATE is the crate name,
CALLBACK is the callback function, BUFFER is the original buffer,
VERSION-CACHE and PENDING-REQUESTS are the hash tables."
  (unwind-protect
      (let* ((response (progn (goto-char (point-min))
                              (re-search-forward "\n\n" nil t)
                              (buffer-substring (point) (point-max))))
             (data (when response
                     (ignore-errors
                       (json-read-from-string response))))
             (crate-info (when data (cdr (assoc 'crate data))))
             (version-str (when crate-info
                            (cdr (assoc 'max_version crate-info))))
             (version (crates--parse-version-string version-str)))
        (when version
          (puthash crate version version-cache))
        (remhash crate pending-requests)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (funcall callback version))))
    (when (buffer-live-p (current-buffer))
      (kill-buffer (current-buffer)))))

(defun crates--create-overlay (version latest)
  "Create an overlay showing the latest version at end of line.
VERSION is the current version, LATEST is the latest available version."
  (let* ((needs-update (crates--version-string-less version latest))
         (display-str (if needs-update
                          (format "  ↑%s" (crates--version-string-to-string latest))
                        (format "  ✓%s " (crates--version-string-to-string latest))))
         (display-str
          (propertize display-str 'face (if needs-update
                                            crates-overlay-outdated-face
                                          crates-overlay-latest-face)))
         (line-end (line-end-position))
         (overlay (make-overlay line-end (1- line-end))))
    (overlay-put overlay 'after-string display-str)
    (overlay-put overlay 'crates t)
    (overlay-put overlay 'evaporate t)
    (push overlay crates--overlays)))

(defun crates--update-overlay-for-dependency (dep &optional force-fetch)
  "Create or update overlay for a single dependency DEP.
If FORCE-FETCH is non-nil, fetch the latest version even if already visited."
  (let* ((crate (plist-get dep :crate))
         (version (plist-get dep :version))
         (pos (plist-get dep :position))
         (buffer (current-buffer))
         (visited-dep-key (format "%s:%s" crate version)))
    (cond
     ;; Fetch if not already visited or if force-fetch is requested
     ((or force-fetch (not (gethash visited-dep-key crates--visited-dependencies)))
      (puthash visited-dep-key t crates--visited-dependencies)
      (crates--fetch-latest-version
       crate
       (lambda (latest)
         (when (and latest (buffer-live-p buffer))
           (with-current-buffer buffer
             (save-excursion
               (goto-char pos)
               (crates--create-overlay version latest)))))))
     ;; If already visited and we have cached version, create overlay immediately
     ((gethash crate crates--version-cache)
      (let ((latest (gethash crate crates--version-cache)))
        (with-current-buffer buffer
          (save-excursion
            (goto-char pos)
            (crates--create-overlay version latest))))))))

;;;###autoload
(defun crates-refresh-overlays ()
  "Refresh all version overlays in the current buffer.
Fetches versions for all dependencies regardless of visited status."
  (interactive)
  (when crates-mode
    (crates--remove-all-overlays)
    (let ((dependencies (crates--find-dependencies)))
      (dolist (dep dependencies)
        (crates--update-overlay-for-dependency dep t)))))

;;;###autoload
(defun crates-refresh-overlays-for-new-dependencies ()
  "Refresh overlays only for new dependencies not yet visited."
  (when crates-mode
    (let ((dependencies (crates--find-dependencies)))
      (dolist (dep dependencies)
        (crates--update-overlay-for-dependency dep nil)))))

;;;###autoload
(defun crates-clear-visited-cache ()
  "Clear the visited dependencies cache.
This will cause all dependencies to be refetched on next refresh."
  (interactive)
  (when crates--visited-dependencies
    (clrhash crates--visited-dependencies))
  (message "Cleared visited dependencies cache"))

(provide 'crates)
;;; crates.el ends here
