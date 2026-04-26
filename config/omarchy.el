;;; omarchy.el --- Omarchy Emacs configuration -*- lexical-binding: t -*-
;;; This file is managed by omarchy-emacs and will be overwritten on updates.
;;; Put your personal customizations in init.el instead.

(require 'subr-x)
(require 'cl-lib)

;; Ensure Omarchy bin is on PATH (needed when started via emacs.service)
(let ((omarchy-bin (expand-file-name "~/.local/share/omarchy/bin")))
  (unless (member omarchy-bin exec-path)
    (add-to-list 'exec-path omarchy-bin)
    (setenv "PATH" (concat omarchy-bin ":" (getenv "PATH")))))

;;; --- Omarchy theme integration ---

(add-to-list 'load-path "~/.config/omarchy/current/theme")
(add-to-list 'custom-theme-load-path "~/.config/emacs/themes")

(defun omarchy-light-theme-p ()
  "Return non-nil if the current Omarchy theme is a light theme."
  (file-exists-p "~/.config/omarchy/current/theme/light.mode"))

(defun omarchy-apply-theme ()
  "Load Omarchy colors and apply them as an Emacs theme."
  (interactive)
  (let ((colors-file (expand-file-name "~/.config/omarchy/current/theme/omarchy-colors.el")))
    (if (file-exists-p colors-file)
        (progn
          (load-file colors-file)
          ;; Fully disable and unload the theme to clear all stale face settings.
          ;; Includes the legacy split themes so upgrades from <1.9 clean up cleanly.
          (dolist (theme '(omarchy omarchy-dark omarchy-light))
            (disable-theme theme)
            (put theme 'theme-settings nil)
            (setq custom-known-themes (delq theme custom-known-themes)))
          (let ((theme-file (locate-file "omarchy-theme"
                                         custom-theme-load-path '(".el"))))
            (load-file theme-file)
            (enable-theme 'omarchy)))
      (message "Omarchy colors not available; skipping theme load."))))

;;; --- Omarchy font integration ---

(defun omarchy--match-in-file (file regex &optional group)
  "Return the GROUP-th match (default 1) when REGEX matches in FILE, or nil."
  (let ((path (expand-file-name file)))
    (when (file-readable-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (when (re-search-forward regex nil t)
          (match-string (or group 1)))))))

(defun omarchy--current-terminal ()
  "Return a symbol naming the active default terminal, or nil.
Possible values: \\='alacritty, \\='kitty, \\='ghostty.
Resolves via ~/.config/xdg-terminals.list, falling back to a probe
of known candidates."
  (let* ((dirs '("~/.local/share/applications"
                 "/usr/share/applications"
                 "/usr/local/share/applications"))
         (installed
          (lambda (entry)
            (and (stringp entry)
                 (not (string-empty-p entry))
                 (cl-some (lambda (d) (file-exists-p (expand-file-name entry d)))
                          dirs))))
         (list-file (expand-file-name "~/.config/xdg-terminals.list"))
         (entries (when (file-readable-p list-file)
                    (with-temp-buffer
                      (insert-file-contents list-file)
                      (mapcar (lambda (l)
                                (string-trim (replace-regexp-in-string "#.*" "" l)))
                              (split-string (buffer-string) "\n")))))
         (entry (or (cl-find-if installed entries)
                    (cl-find-if installed
                                '("com.mitchellh.ghostty.desktop"
                                  "kitty.desktop"
                                  "Alacritty.desktop")))))
    (when entry
      (cond
       ((string-match-p "[Aa]lacritty" entry) 'alacritty)
       ((string-match-p "kitty" entry) 'kitty)
       ((string-match-p "ghostty" entry) 'ghostty)))))

(defun omarchy--terminal-config-file ()
  "Return the active terminal's config file path, or nil."
  (pcase (omarchy--current-terminal)
    ('alacritty (expand-file-name "~/.config/alacritty/alacritty.toml"))
    ('kitty     (expand-file-name "~/.config/kitty/kitty.conf"))
    ('ghostty   (expand-file-name "~/.config/ghostty/config"))))

(defun omarchy--terminal-font-size ()
  "Return the font size from the active terminal's config, or nil.
Returned as a string like \"11.5\"."
  (pcase (omarchy--current-terminal)
    ('alacritty
     ;; Restrict to the [font] section so unrelated `size =` entries don't win.
     (let ((file (expand-file-name "~/.config/alacritty/alacritty.toml")))
       (when (file-readable-p file)
         (with-temp-buffer
           (insert-file-contents file)
           (goto-char (point-min))
           (when (re-search-forward "^\\[font\\][ \t]*$" nil t)
             (let ((bound (or (save-excursion
                                (when (re-search-forward "^\\[" nil t)
                                  (match-beginning 0)))
                              (point-max))))
               (when (re-search-forward
                      "^size[ \t]*=[ \t]*\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"
                      bound t)
                 (match-string 1))))))))
    ('kitty
     (omarchy--match-in-file "~/.config/kitty/kitty.conf"
                             "^font_size[ \t]+\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"))
    ('ghostty
     (omarchy--match-in-file "~/.config/ghostty/config"
                             "^font-size[ \t]*=[ \t]*\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"))))

(defun omarchy-current-font ()
  "Return the current Omarchy monospace font family from Waybar's stylesheet."
  (or (omarchy--match-in-file "~/.config/waybar/style.css"
                              "font-family:[ \t]*[\"']?\\([^;\"'\n]+\\)")
      ""))

(defun omarchy-current-font-size ()
  "Return the current Omarchy font size in Emacs height units (1/10 pt).
The pgtk build handles display scaling natively, so no adjustment is needed.
For X11 builds running under XWayland, scale by the monitor factor."
  (let ((size (omarchy--terminal-font-size))
        (scale (if (featurep 'pgtk)
                   1.0
                 (let ((s (string-to-number
                           (string-trim
                            (shell-command-to-string
                             "hyprctl monitors | grep -oP 'scale:\\s*\\K[0-9]+\\.?[0-9]*' | head -1")))))
                   (if (or (zerop s) (< s 1)) 1.0 s)))))
    (if size
        (round (* (string-to-number size) scale 10))
      120)))

(defun omarchy-apply-font ()
  "Set the Emacs default font to match Omarchy."
  (interactive)
  (let ((font (omarchy-current-font))
        (height (omarchy-current-font-size)))
    (when (and font (not (string-empty-p font)))
      (set-face-attribute 'default nil :family font :height height)
      (dolist (frame (frame-list))
        (set-face-attribute 'default frame :family font :height height))
      (add-to-list 'default-frame-alist `(font . ,(format "%s-%g" font (/ height 10.0)))))))

;;; --- Clean UI ---

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(set-frame-parameter nil 'internal-border-width 8)
(add-to-list 'default-frame-alist '(internal-border-width . 8))

;; Apply on startup
(omarchy-apply-theme)
(omarchy-apply-font)

;; Watch for theme changes so Emacs reloads from within its own event loop.
;; We watch theme.name (not the theme/ directory) because theme-set does
;; rm -rf + mv on the directory, which destroys inotify watches.
(require 'filenotify)
(defvar omarchy--theme-watch nil "File notification descriptor for theme changes.")
(let ((theme-name-file (expand-file-name "~/.config/omarchy/current/theme.name")))
  (when (file-exists-p theme-name-file)
    (when omarchy--theme-watch
      (file-notify-rm-watch omarchy--theme-watch))
    (setq omarchy--theme-watch
          (file-notify-add-watch
           theme-name-file '(change)
           (lambda (_event)
             (omarchy-apply-theme)
             (omarchy-apply-font))))))

;; Watch for terminal config changes so font size updates are picked up.
(defvar omarchy--terminal-watch nil "File notification descriptor for terminal config changes.")
(let ((config-file (omarchy--terminal-config-file)))
  (when (and config-file (file-exists-p config-file))
    (when omarchy--terminal-watch
      (file-notify-rm-watch omarchy--terminal-watch))
    (setq omarchy--terminal-watch
          (file-notify-add-watch
           config-file '(change)
           (lambda (_event)
             (omarchy-apply-font))))))

;; Start the Emacs server
(require 'server)
(unless (server-running-p)
  (server-start))

;;; --- Shell configuration ---

(setq explicit-shell-file-name "/bin/bash")
(setq explicit-bash-args
      `("--noediting" "--rcfile"
        ,(expand-file-name "shell-bashrc" user-emacs-directory) "-i"))
(setq shell-command-switch "-lc")
(setq comint-terminfo-terminal "xterm-256color")

(add-hook 'shell-mode-hook
          (lambda ()
            (add-hook 'comint-preoutput-filter-functions
                      (lambda (text)
                        (replace-regexp-in-string "\033\\][0-9]+;[^\007\033]*[\007\033\\\\]" "" text))
                      nil t)))

;;; --- Strip trailing whitespace on save ---

(add-hook 'before-save-hook #'delete-trailing-whitespace)

;;; omarchy.el ends here
