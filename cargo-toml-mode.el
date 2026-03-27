;;; cargo-toml-mode.el --- Minor mode for Cargo.toml with crate version overlays -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2026 shadr
;;
;; Author: shadr <shadr@nixos>
;; Maintainer: shadr <shadr@nixos>
;; Version: 0.1.0
;; Homepage: https://github.com/shadr/cargo-toml-mode
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
;;
;; Usage:
;; Enable with `M-x cargo-toml-mode' or add to hook:
;;   (add-hook 'toml-mode-hook #'cargo-toml-mode)
;;
;; Keybindings:
;; - `C-c C-l' - Update latest version at point
;; - `C-c C-a' - Update all crate versions
;; - `C-c C-r' - Refresh all overlays
;;
;;; Code:

(require 'json)
(require 'url)
(require 'subr-x)

(require 'cargo-toml-mode-utils)

(defgroup cargo-toml nil
  "Minor mode for Cargo.toml files with crate version overlays."
  :group 'tools
  :prefix "cargo-toml-")

(defcustom cargo-toml-overlay-latest-face 'cargo-toml-latest-version
  "Face used to display the latest version overlay."
  :type 'face
  :group 'cargo-toml)

(defcustom cargo-toml-overlay-oudated-face 'cargo-toml-outdated-version
  "Face used to display the outdated version overlay."
  :type 'face
  :group 'cargo-toml)

(defcustom cargo-toml-fetch-timeout 10
  "Timeout in seconds for fetching crate version information."
  :type 'integer
  :group 'cargo-toml)

(defface cargo-toml-latest-version
  '((t (:foreground "#505050" :slant italic :height 0.8)))
  "Face for displaying latest crate version."
  :group 'cargo-toml)

(defface cargo-toml-outdated-version
  '((t (:foreground "#f9e2af" :slant italic :height 0.8)))
  "Face for displaying outdated crate version."
  :group 'cargo-toml)

(defvar-local cargo-toml--overlays nil
  "List of active version overlays in the current buffer.")

(defvar-local cargo-toml--version-cache nil
  "Cache of fetched crate versions for the current buffer.")

(defvar-local cargo-toml--pending-requests nil
  "Track pending async requests to avoid duplicates in current buffer.")

(defun cargo-toml--init-buffers-local-vars ()
  "Initialize buffer-local variables."
  (unless cargo-toml--version-cache
    (setq cargo-toml--version-cache (make-hash-table :test 'equal)))
  (unless cargo-toml--pending-requests
    (setq cargo-toml--pending-requests (make-hash-table :test 'equal))))

;;;###autoload
(define-minor-mode cargo-toml-mode
  "Minor mode for editing Cargo.toml files.

Displays the latest available version of crates as virtual text
at the end of dependency declaration lines.

Commands:
\\{cargo-toml-mode-map}"
  :lighter " Cargo"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-c C-l") #'cargo-toml-update-version-at-point)
            (define-key map (kbd "C-c C-a") #'cargo-toml-update-all-versions)
            (define-key map (kbd "C-c C-r") #'cargo-toml-refresh-overlays)
            map)
  (if cargo-toml-mode
      (cargo-toml--enable)
    (cargo-toml--disable)))

(defun cargo-toml--enable ()
  "Enable cargo-toml-mode."
  (cargo-toml--init-buffers-local-vars)
  (cargo-toml-refresh-overlays)
  (add-hook 'after-change-functions #'cargo-toml--after-change nil t)
  (add-hook 'kill-buffer-hook #'cargo-toml--cleanup nil t))

(defun cargo-toml--disable ()
  "Disable cargo-toml-mode."
  (cargo-toml--remove-all-overlays)
  (remove-hook 'after-change-functions #'cargo-toml--after-change t)
  (remove-hook 'kill-buffer-hook #'cargo-toml--cleanup t))

(defun cargo-toml--cleanup ()
  "Clean up overlays and cache when buffer is killed."
  (cargo-toml--remove-all-overlays)
  (when cargo-toml--version-cache
    (clrhash cargo-toml--version-cache))
  (when cargo-toml--pending-requests
    (clrhash cargo-toml--pending-requests))
  (setq cargo-toml--version-cache nil)
  (setq cargo-toml--pending-requests nil))

(defun cargo-toml--remove-all-overlays ()
  "Remove all cargo-toml overlays from the current buffer."
  (mapc #'delete-overlay cargo-toml--overlays)
  (setq cargo-toml--overlays nil))

(defun cargo-toml--after-change (_beg _end _len)
  "Handle buffer changes.
_BEG, _END, and _LEN are the change boundaries and length."
  (when cargo-toml-mode
    (cargo-toml--remove-all-overlays)
    (cargo-toml-refresh-overlays)))

(defvar-local cargo-toml--in-dependencies-section nil
  "Track if we're currently in a dependencies section.")

(defun cargo-toml--parse-dependency-line ()
  "Parse the current line for a dependency declaration.

Returns a plist with :crate and :version if found, nil otherwise."
  (save-excursion
    (beginning-of-line)
    ;; Check if we're entering/exiting a dependencies section
    (let ((line (thing-at-point 'line t)))
      ;; Track section changes
      (when (string-match "^\\s-*\\[\\(.*dependencies.*\\)\\]" line)
        (setq cargo-toml--in-dependencies-section t))
      (when (and (string-match "^\\s-*\\[" line)
                 (not (string-match "^\\[.*dependencies" line)))
        (setq cargo-toml--in-dependencies-section nil))
      ;; Only parse if in dependencies section
      (when cargo-toml--in-dependencies-section
        (cond
         ;; Simple format: crate = "version"
         ((string-match "^\\s-*\\([a-zA-Z0-9_-]+\\)\\s-*=\\s-*\"\\([^\"]+\\)\"" line)
          (let ((crate (match-string 1 line))
                (version (match-string 2 line)))
            (unless (string-prefix-p "{" version)
              (list :crate crate :version (cargo-toml--parse-version-string version)))))
         ;; Table format: crate = { version = "..." }
         ((string-match "^\\s-*\\([a-zA-Z0-9_-]+\\)\\s-*=\\s-*{" line)
          (let ((crate (match-string 1 line)))
            (when (string-match "version\\s-*=\\s-*\"\\([^\"]+\\)\"" line)
              (list :crate crate :version (cargo-toml--parse-version-string (match-string 1 line)))))))))))

(defun cargo-toml--find-dependencies ()
  "Find all dependency declarations in the buffer.

Returns a list of plists with :crate, :version, and :position."
  (save-excursion
    (goto-char (point-min))
    ;; Reset section tracking
    (setq cargo-toml--in-dependencies-section nil)
    (let (dependencies)
      (while (not (eobp))
        (let ((dep (cargo-toml--parse-dependency-line)))
          (when dep
            (push (nconc dep (list :position (point))) dependencies)))
        (forward-line 1))
      (nreverse dependencies))))

(defun cargo-toml--fetch-latest-version (crate callback)
  "Fetch the latest version of CRATE from crates.io.
CALLBACK is called with the version string or nil on error."
  (print "making a fetch request")
  (let ((cached (gethash crate cargo-toml--version-cache))
        (buffer (current-buffer))
        (version-cache cargo-toml--version-cache)
        (pending-requests cargo-toml--pending-requests))
    (if cached
        (funcall callback cached)
      (let ((url (format "https://crates.io/api/v1/crates/%s" crate)))
        (unless (gethash crate pending-requests)
          (puthash crate t pending-requests)
          (let ((process-environment process-environment))
            (url-retrieve url
                          (lambda (status)
                            (cargo-toml--handle-response status crate callback buffer version-cache pending-requests))
                          nil t t)))))))

(defun cargo-toml--handle-response (status crate callback buffer version-cache pending-requests)
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
             (version (cargo-toml--parse-version-string version-str)))
        (when version
          (puthash crate version version-cache))
        (remhash crate pending-requests)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (funcall callback version))))
    (when (buffer-live-p (current-buffer))
      (kill-buffer (current-buffer)))))

(defun cargo-toml--create-overlay (version latest)
  "Create an overlay showing the latest version at end of line.
LINE-END is the end of line position, VERSION is the current version,
LATEST is the latest available version."
  (let* ((needs-update (version-string-less version latest))
         (display-str (if needs-update
                          (format "  ↑%s" (version-string-to-string latest))
                        (format "  ✓%s " (version-string-to-string latest))))
         (display-str
          (propertize display-str 'face (if needs-update
                                            cargo-toml-overlay-oudated-face
                                          cargo-toml-overlay-latest-face)))
         (line-end (line-end-position))
         (overlay (make-overlay line-end (1- line-end))))
    (overlay-put overlay 'after-string display-str)
    (overlay-put overlay 'cargo-toml t)
    (overlay-put overlay 'evaporate t)
    (push overlay cargo-toml--overlays)
    (message "Created overlay for %s: %s -> %s" version latest display-str)))

(defun cargo-toml--update-overlay-for-dependency (dep)
  "Create or update overlay for a single dependency DEP."
  (let ((crate (plist-get dep :crate))
        (version (plist-get dep :version))
        (pos (plist-get dep :position))
        (buffer (current-buffer)))
    (cargo-toml--fetch-latest-version
     crate
     (lambda (latest)
       (when (and latest (buffer-live-p buffer))
         (with-current-buffer buffer
           (save-excursion
             (goto-char pos)
             (message "Found version string, comparing %s < %s = %s"
                      version latest (version-string-less version latest))
             (cargo-toml--create-overlay version latest))))))))

;;;###autoload
(defun cargo-toml-refresh-overlays ()
  "Refresh all version overlays in the current buffer."
  (interactive)
  (when cargo-toml-mode
    (cargo-toml--remove-all-overlays)
    (let ((dependencies (cargo-toml--find-dependencies)))
      (dolist (dep dependencies)
        (cargo-toml--update-overlay-for-dependency dep)))))

;;;###autoload
(defun cargo-toml-update-version-at-point ()
  "Update the crate version at point to the latest available version."
  (interactive)
  (let ((dep (cargo-toml--parse-dependency-line)))
    (when dep
      (let ((crate (plist-get dep :crate))
            (version (plist-get dep :version))
            (pos (plist-get dep :position))
            (buffer (current-buffer)))
        (cargo-toml--fetch-latest-version
         crate
         (lambda (latest)
           (when (and latest (buffer-live-p buffer))
             (with-current-buffer buffer
               (save-excursion
                 (goto-char pos)
                 (beginning-of-line)
                 (when (re-search-forward (format "\"%s\"" (regexp-quote version))
                                          (line-end-position) t)
                   (replace-match (format "\"%s\"" latest) t t nil 0)
                   (message "Updated %s to version %s" crate latest)))))))))))

;;;###autoload
(defun cargo-toml-update-all-versions ()
  "Update all crate versions in the buffer to their latest available versions."
  (interactive)
  (let ((dependencies (cargo-toml--find-dependencies)))
    (if (null dependencies)
        (message "No dependencies found")
      (message "Updating %d dependencies..." (length dependencies))
      (let ((count 0)
            (buffer (current-buffer)))
        (dolist (dep dependencies)
          (let ((crate (plist-get dep :crate))
                (version (plist-get dep :version))
                (pos (plist-get dep :position)))
            (cargo-toml--fetch-latest-version
             crate
             (lambda (latest)
               (when (and latest (buffer-live-p buffer))
                 (with-current-buffer buffer
                   (save-excursion
                     (goto-char pos)
                     (beginning-of-line)
                     (when (re-search-forward (format "\"%s\"" (regexp-quote version))
                                              (line-end-position) t)
                       (replace-match (format "\"%s\"" latest) t t nil 0)
                       (cl-incf count)
                       (message "Updated %d/%d dependencies" count (length dependencies))))))))))
        (run-at-time 2 nil (lambda () (message "Updated %d dependencies" count)))))))

;; ;;;###autoload
;; (add-to-list 'auto-mode-alist '("Cargo\\.toml\\'" . cargo-toml-mode))

(provide 'cargo-toml-mode)
;;; cargo-toml-mode.el ends here
