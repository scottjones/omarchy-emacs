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

;; Omarchy 4 moved the active theme out of ~/.config/omarchy/current/ into
;; XDG state (~/.local/state/omarchy/current/). Resolve whichever base a
;; given machine uses so the integration works on both Omarchy 3 and 4:
;; prefer the new location, fall back to the old, and default to the new
;; one when neither exists yet (fresh install before the first theme-set).
(defun omarchy--current-base ()
  "Return the directory holding Omarchy's current theme assets."
  (let ((candidates (list (expand-file-name "~/.local/state/omarchy/current")
                          (expand-file-name "~/.config/omarchy/current"))))
    (or (cl-find-if (lambda (d) (file-directory-p (expand-file-name "theme" d)))
                    candidates)
        (car candidates))))

(defvar omarchy-theme-directory
  (expand-file-name "theme" (omarchy--current-base))
  "Directory holding the current Omarchy theme's generated assets.")
(defvar omarchy-theme-name-file
  (expand-file-name "theme.name" (omarchy--current-base))
  "File holding the current Omarchy theme name; watched for theme changes.")

(add-to-list 'load-path omarchy-theme-directory)
(add-to-list 'custom-theme-load-path "~/.config/emacs/themes")

(defun omarchy-light-theme-p ()
  "Return non-nil if the current Omarchy theme is a light theme.
Omarchy 4 records the mode in colors.toml (`mode = \"light\"'); older
themes signalled it with a light.mode marker file, still honored here."
  (or (file-exists-p (expand-file-name "light.mode" omarchy-theme-directory))
      (let ((colors (expand-file-name "colors.toml" omarchy-theme-directory)))
        (and (file-readable-p colors)
             (with-temp-buffer
               (insert-file-contents colors)
               (goto-char (point-min))
               (and (re-search-forward
                     "^[ \t]*mode[ \t]*=[ \t]*[\"']?light[\"']?[ \t]*$" nil t)
                    t))))))

(defun omarchy-apply-theme ()
  "Load Omarchy colors and apply them as an Emacs theme."
  (interactive)
  (let ((colors-file (expand-file-name "omarchy-colors.el" omarchy-theme-directory)))
    (if (file-exists-p colors-file)
        (progn
          ;; omarchy-colors.el `setq's only the colors its template rendered,
          ;; so switching from a semantic theme to a legacy color0..15 one
          ;; would leave the previous theme's semantic colors bound and in
          ;; use. Clear them first so the theme sees a genuinely absent value.
          (dolist (sym '(omarchy-color-muted omarchy-color-selection
                         omarchy-color-dark-fg omarchy-color-light-fg
                         omarchy-color-bright-fg omarchy-color-dark-bg
                         omarchy-color-darker-bg omarchy-color-lighter-bg
                         omarchy-color-orange))
            (makunbound sym))
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
Possible values: \\='foot, \\='alacritty, \\='kitty, \\='ghostty.
Resolves via ~/.config/xdg-terminals.list, falling back to a probe
of known candidates. Foot leads the probe list: it is Omarchy 4's default
terminal and the only one a fresh install ships, and `omarchy-default-terminal'
only writes xdg-terminals.list once the user picks a terminal explicitly —
so on a fresh install the probe is all we have. Foot is absent on Omarchy 3,
where the probe skips it and the old order stands."
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
                                '("foot.desktop"
                                  "com.mitchellh.ghostty.desktop"
                                  "kitty.desktop"
                                  "Alacritty.desktop")))))
    (when entry
      (cond
       ((string-match-p "[Aa]lacritty" entry) 'alacritty)
       ((string-match-p "kitty" entry) 'kitty)
       ((string-match-p "ghostty" entry) 'ghostty)
       ;; Match foot last: it is a substring of nothing else here, but
       ;; "foot-server.desktop"/"footclient.desktop" are also valid entries.
       ((string-match-p "foot" entry) 'foot)))))

(defun omarchy--terminal-config-file ()
  "Return the active terminal's config file path, or nil."
  (pcase (omarchy--current-terminal)
    ('alacritty (expand-file-name "~/.config/alacritty/alacritty.toml"))
    ('kitty     (expand-file-name "~/.config/kitty/kitty.conf"))
    ('ghostty   (expand-file-name "~/.config/ghostty/config"))
    ('foot      (expand-file-name "~/.config/foot/foot.ini"))))

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
                             "^font-size[ \t]*=[ \t]*\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"))
    ('foot
     ;; Foot carries the size in the font spec itself:
     ;;   font=JetBrainsMono Nerd Font:size=9
     ;; Anchor on the `font=' key so `font-bold'/`font-italic' can't win.
     (omarchy--match-in-file "~/.config/foot/foot.ini"
                             "^font[ \t]*=[^\n]*:size=\\([0-9]+\\(?:\\.[0-9]+\\)?\\)"))))

(defun omarchy--terminal-font-family ()
  "Return the font family configured in the active terminal, or nil.
This is the family the user actually sees: `omarchy-font-set' always
rewrites it, whereas the fontconfig `monospace' alias can be shadowed by a
system conf.d rule (e.g. /etc/fonts/conf.d/50-omarchy.conf) and never
reflect the user's choice."
  (pcase (omarchy--current-terminal)
    ('alacritty
     ;; Restrict to the [font] section so an unrelated `family =` won't win.
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
                      "family[ \t]*=[ \t]*[\"']\\([^\"']+\\)[\"']" bound t)
                 (match-string 1))))))))
    ('kitty
     (omarchy--match-in-file "~/.config/kitty/kitty.conf"
                             "^font_family[ \t]+\\(.+?\\)[ \t]*$"))
    ('ghostty
     (omarchy--match-in-file "~/.config/ghostty/config"
                             "^font-family[ \t]*=[ \t]*[\"']?\\([^\"'\n]+?\\)[\"']?[ \t]*$"))
    ('foot
     (omarchy--match-in-file "~/.config/foot/foot.ini"
                             "^font[ \t]*=[ \t]*\\([^:\n]+\\)"))))

(defun omarchy-current-font ()
  "Return the font family Emacs should use to match Omarchy.
Prefer the active terminal's configured family — it is what the user
actually sees, and `omarchy-font-set' keeps it current. Fall back to the
fontconfig `monospace' alias (via `omarchy-font-current'), then to Waybar
for older Omarchy versions. The alias is only a fallback because a system
conf.d rule can shadow the user's fontconfig override, leaving the alias
stuck on the packaged default while the terminal shows the chosen font."
  (or (let ((fam (omarchy--terminal-font-family)))
        (and fam (setq fam (string-trim fam))
             (not (string-empty-p fam)) fam))
      (and (executable-find "omarchy-font-current")
           (let ((f (string-trim (shell-command-to-string "omarchy-font-current"))))
             (and (not (string-empty-p f)) f)))
      (omarchy--match-in-file "~/.config/waybar/style.css"
                              "font-family:[ \t]*[\"']?\\([^;\"'\n]+\\)")
      ""))

(defun omarchy-current-font-size ()
  "Return the intended Omarchy font size in Emacs height units (1/10 pt).
This mirrors the active terminal's point size; `omarchy-apply-font' realizes
it per display backend. Defaults to 12pt when no terminal size is found."
  (let ((size (omarchy--terminal-font-size)))
    (round (* (if size (string-to-number size) 12.0) 10))))

(defun omarchy-apply-font ()
  "Set the Emacs default font to match Omarchy.
On the pgtk build, specify an absolute PIXEL size rather than a point size.
Omarchy 4's `omarchy display text size' folds its scaling into BOTH the
terminal point size we mirror AND GNOME's text-scaling-factor, and pgtk
applies that factor to point-sized fonts — so a point size renders scaled
twice and ends up larger than the terminal. A pixel size sidesteps the GTK
factor (and its startup-only caching, which otherwise lags live size changes),
so Emacs matches the terminal at any size; Wayland's per-output surface
scaling still handles HiDPI. 1pt = 1/72in at GTK's 96 logical DPI, so
px = pt * 96/72. X11/XWayland builds ignore the GTK factor and get no surface
scaling, so they keep a point size scaled by the monitor factor."
  (let ((font (omarchy-current-font))
        (pt (/ (omarchy-current-font-size) 10.0)))
    (when (and font (not (string-empty-p font)))
      (let ((spec
             (if (featurep 'pgtk)
                 (format "%s:pixelsize=%d" font (max 1 (round (* pt (/ 96.0 72.0)))))
               (let ((s (string-to-number
                         (string-trim
                          (shell-command-to-string
                           "hyprctl monitors | grep -oP 'scale:\\s*\\K[0-9]+\\.?[0-9]*' | head -1")))))
                 (format "%s-%g" font (* pt (if (or (zerop s) (< s 1)) 1.0 s)))))))
        ;; Set the default face (covers new frames and inheriting faces)...
        (set-face-attribute 'default nil :font spec)
        ;; ...then retag each live graphical frame (set-face-attribute alone
        ;; only takes on newly-created frames).
        (dolist (frame (frame-list))
          (when (display-graphic-p frame)
            (set-frame-font spec nil (list frame))))
        ;; Replace (not append) so default-frame-alist doesn't accumulate.
        (setf (alist-get 'font default-frame-alist) spec)))))

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
(let ((theme-name-file omarchy-theme-name-file))
  (when (file-exists-p theme-name-file)
    (when omarchy--theme-watch
      (file-notify-rm-watch omarchy--theme-watch))
    (setq omarchy--theme-watch
          (file-notify-add-watch
           theme-name-file '(change)
           (lambda (_event)
             (omarchy-apply-theme)
             (omarchy-apply-font))))))

;; Watch font sources so size and family changes are picked up live.
;; Size lives in the terminal config; the family source moved to fontconfig
;; in Omarchy 4 (Waybar is no longer updated) and was Waybar's stylesheet
;; before that. Watch all applicable sources — a file that never changes is
;; a harmless watch, and the managed font-set hook reloads us regardless.
(defvar omarchy--font-watches nil
  "File notification descriptors for font-related files.")
(dolist (desc omarchy--font-watches)
  (ignore-errors (file-notify-rm-watch desc)))
(setq omarchy--font-watches nil)
(dolist (file (delq nil (list (omarchy--terminal-config-file)
                              (expand-file-name "~/.config/fontconfig/fonts.conf")
                              (expand-file-name "~/.config/waybar/style.css"))))
  (when (file-exists-p file)
    (push (file-notify-add-watch
           file '(change)
           (lambda (_event) (omarchy-apply-font)))
          omarchy--font-watches)))

;; Migrate existing installs to drop-in hooks for users who upgrade via pacman
;; without re-running omarchy-emacs-setup. Cheap guard: once the drop-in exists,
;; skip entirely (no subprocess). Async (destination 0) with errors ignored so
;; startup never blocks. Guarded on omarchy-hook-install — the Omarchy 4 signal,
;; since only O4 supports the <type>.d/ layout the sync script writes.
(when (and (executable-find "omarchy-hook-install")
           (not (file-exists-p
                 (expand-file-name "~/.config/omarchy/hooks/theme-set.d/omarchy-emacs")))
           (executable-find "omarchy-emacs-sync-hooks"))
  (ignore-errors (call-process "omarchy-emacs-sync-hooks" nil 0 nil)))

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
