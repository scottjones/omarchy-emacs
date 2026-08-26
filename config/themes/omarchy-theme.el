;;; omarchy-theme.el --- Omarchy theme synced from system colors -*- lexical-binding: t -*-

(deftheme omarchy "Omarchy theme synced from system colors.")

(require 'cl-lib)
(require 'omarchy-colors)

;;; Derived shades.
;;
;; The 16 ANSI slots plus fg/bg/accent/cursor leave no shade in between, so UI
;; chrome (current-line stripe, inactive mode line, borders, comments) used to
;; borrow whichever slot was closest -- usually bright-black or bright-white,
;; a different hue than the background, which reads as grime on many themes.
;;
;; Omarchy 4 does ship those in-between shades, just not under ANSI names:
;; `muted', `dark_foreground', `lighter_background' and `selection' are in
;; every semantic colors.toml and reach us through the color template. Prefer
;; them, since they are what the theme's author actually chose. Two things
;; still need doing to them:
;;
;;   - A shade may not be usable. Omarchy synthesizes the semantic keys even
;;     for legacy color0..color15 themes, but it can only synthesize them from
;;     what is there -- grimdark-solarized comes back with `lighter_background'
;;     equal to its own background, which would make the stripe invisible. An
;;     install whose template predates the semantic block renders them empty.
;;     Blend a replacement from the theme's own foreground and background --
;;     in-family, and it tracks light vs dark for free, since on a light theme
;;     the mix darkens and on a dark theme it lightens.
;;
;;   - They are picked for terminal chrome, not for Emacs. Several sit a bare
;;     shade off the background, and `muted' on `selection' is two steps of
;;     one ramp. Keep the hue, raise the contrast to a floor.
;;
;; Between them these remove every light/dark branch this theme used to carry.

(defgroup omarchy nil
  "Emacs theme and font synced from the current Omarchy theme."
  :group 'faces
  :prefix "omarchy-")

(defun omarchy--hex-rgb (color)
  "Return (R G B) as integers 0-255 for COLOR, or nil if it is not #RRGGBB."
  (when (and (stringp color)
             (string-match "\\`#\\([0-9a-fA-F]\\{6\\}\\)\\'" color))
    (let ((n (string-to-number (match-string 1 color) 16)))
      (list (ash n -16) (logand (ash n -8) 255) (logand n 255)))))

(defun omarchy-blend (fg bg alpha)
  "Mix FG over BG at ALPHA, where 1.0 is all FG and 0.0 is all BG.
Falls back to FG when either color is not plain #RRGGBB hex."
  (let ((a (omarchy--hex-rgb fg))
        (b (omarchy--hex-rgb bg)))
    (if (and a b)
        (apply #'format "#%02x%02x%02x"
               (cl-mapcar (lambda (x y) (round (+ (* alpha x) (* (- 1.0 alpha) y))))
                          a b))
      fg)))

(defcustom omarchy-contrast-floor-text 4.5
  "Minimum contrast ratio for chrome that carries text you read.
Applies to the inactive mode line and the header line."
  :type 'number :group 'omarchy)

(defcustom omarchy-contrast-floor-dim 3.0
  "Minimum contrast ratio for deliberately de-emphasized text.
Applies to comments and line numbers, which are meant to recede."
  :type 'number :group 'omarchy)

(defun omarchy--luminance (color)
  "WCAG relative luminance of COLOR, or nil if it is not #RRGGBB."
  (let ((rgb (omarchy--hex-rgb color)))
    (when rgb
      (cl-loop for c in rgb
               for w in '(0.2126 0.7152 0.0722)
               sum (* w (let ((v (/ c 255.0)))
                          (if (<= v 0.03928)
                              (/ v 12.92)
                            (expt (/ (+ v 0.055) 1.055) 2.4))))))))

(defun omarchy--contrast (a b)
  "WCAG contrast ratio between A and B, or 1.0 if either is unusable."
  (let ((la (omarchy--luminance a))
        (lb (omarchy--luminance b)))
    (if (and la lb)
        (/ (+ (max la lb) 0.05) (+ (min la lb) 0.05))
      1.0)))

(defun omarchy--readable (fg bg floor)
  "FG pushed away from BG until it reaches FLOOR contrast.
Omarchy's semantic colors are chosen for terminal chrome, where several
sit only a shade off the background -- `muted' on `selection' is two
steps of the same ramp. Keep the hue the theme picked and walk it toward
white or black, whichever BG is not, only as far as legibility needs."
  (if (or (not (omarchy--hex-rgb fg))
          (not (omarchy--hex-rgb bg))
          (>= (omarchy--contrast fg bg) floor))
      fg
    (let ((target (if (< (omarchy--luminance bg) 0.5) "#ffffff" "#000000")))
      (cl-loop for step from 1 to 20
               for mixed = (omarchy-blend target fg (* step 0.05))
               when (>= (omarchy--contrast mixed bg) floor) return mixed
               finally return target))))

(defun omarchy--pick (symbol fallback &optional distinct-from)
  "Value of SYMBOL when it is a usable #RRGGBB string, else FALLBACK.
A value is unusable when it is missing -- an install whose color template
predates the semantic block renders these as an empty string, and loading
such a file leaves the variable unbound -- or when it equals DISTINCT-FROM,
which themes do for `lighter_background' and `selection' often enough to
matter, and which would leave the stripe or the region invisible.

Note that omarchy-theme-color synthesizes the semantic keys for legacy
color0..color15 themes as well, so a legacy theme is not by itself a
reason to fall back; it is the equal-to-background case that usually is."
  (let ((v (and (boundp symbol) (symbol-value symbol))))
    (if (and (omarchy--hex-rgb v)
             (not (and distinct-from (equal v distinct-from))))
        v
      fallback)))

(let* ((bg omarchy-color-bg)
       (fg omarchy-color-fg)
       ;; Prefer the shade the theme's author actually chose; blend one only
       ;; when the theme does not carry it.
       (bg-subtle    (omarchy--pick 'omarchy-color-lighter-bg
                                    (omarchy-blend fg bg 0.06) bg))
       (bg-highlight (omarchy--pick 'omarchy-color-selection
                                    (omarchy-blend fg bg 0.13) bg))
       (border       (omarchy--pick 'omarchy-color-muted
                                    (omarchy-blend fg bg 0.28) bg))
       ;; Foregrounds keep the theme's hue but not its terminal-chrome
       ;; contrast; each is raised to the floor for the ground it sits on.
       (fg-comment   (omarchy--readable
                      (omarchy--pick 'omarchy-color-dark-fg
                                     (omarchy-blend fg bg 0.52) bg)
                      bg omarchy-contrast-floor-dim))
       (fg-faint     (omarchy--readable
                      (omarchy--pick 'omarchy-color-muted
                                     (omarchy-blend fg bg 0.38) bg)
                      bg omarchy-contrast-floor-dim))
       ;; The inactive mode line sits on `bg-highlight', not on the buffer
       ;; background, and it carries the buffer name -- so it gets the text
       ;; floor against its own ground.
       (fg-chrome    (omarchy--readable
                      (omarchy--pick 'omarchy-color-muted
                                     (omarchy-blend fg bg 0.38) bg-highlight)
                      bg-highlight omarchy-contrast-floor-text))
       ;; `colors.toml' is authoritative for the selection, but a few themes
       ;; set it equal to the background, which makes the region invisible.
       (region-bg    (if (equal omarchy-color-sel-bg bg)
                         bg-highlight
                       omarchy-color-sel-bg)))
  (custom-theme-set-faces
   'omarchy

   ;; Core faces
   `(default ((t (:foreground ,fg :background ,bg))))
   `(cursor ((t (:background ,omarchy-color-cursor))))
   `(region ((t (:foreground ,omarchy-color-sel-fg :background ,region-bg))))
   `(highlight ((t (:background ,bg-highlight))))
   `(hl-line ((t (:background ,bg-subtle))))
   `(fringe ((t (:background ,bg))))
   `(vertical-border ((t (:foreground ,border))))

   ;; Mode line
   `(mode-line ((t (:foreground ,bg :background ,omarchy-color-accent :box nil))))
   `(mode-line-inactive ((t (:foreground ,fg-chrome :background ,bg-highlight :box nil))))
   `(header-line ((t (:foreground ,fg-chrome :background ,bg-highlight :box nil))))
   `(mode-line-buffer-id ((t (:weight bold))))

   ;; Line numbers
   `(line-number ((t (:foreground ,fg-faint :background ,bg))))
   `(line-number-current-line ((t (:foreground ,omarchy-color-accent :background ,bg-subtle :weight bold))))

   ;; Minibuffer / prompts
   `(minibuffer-prompt ((t (:foreground ,omarchy-color-accent :weight bold))))

   ;; Search
   `(isearch ((t (:foreground ,bg :background ,omarchy-color-yellow))))
   `(lazy-highlight ((t (:foreground ,bg :background ,omarchy-color-bright-yellow))))

   ;; Font lock (syntax highlighting)
   `(font-lock-keyword-face ((t (:foreground ,omarchy-color-magenta))))
   `(font-lock-function-name-face ((t (:foreground ,omarchy-color-blue))))
   `(font-lock-function-call-face ((t (:foreground ,omarchy-color-blue))))
   `(font-lock-variable-name-face ((t (:foreground ,fg))))
   `(font-lock-string-face ((t (:foreground ,omarchy-color-green))))
   `(font-lock-comment-face ((t (:foreground ,fg-comment :slant italic))))
   `(font-lock-comment-delimiter-face ((t (:foreground ,fg-comment :slant italic))))
   `(font-lock-type-face ((t (:foreground ,omarchy-color-yellow))))
   `(font-lock-constant-face ((t (:foreground ,omarchy-color-white))))
   `(font-lock-builtin-face ((t (:foreground ,omarchy-color-cyan))))
   `(font-lock-preprocessor-face ((t (:foreground ,omarchy-color-red))))
   `(font-lock-warning-face ((t (:foreground ,omarchy-color-red :weight bold))))
   `(font-lock-doc-face ((t (:foreground ,omarchy-color-bright-green))))
   `(font-lock-number-face ((t (:foreground ,omarchy-color-white))))
   `(font-lock-negation-char-face ((t (:foreground ,omarchy-color-red))))
   `(font-lock-operator-face ((t (:foreground ,omarchy-color-cyan))))

   ;; Parentheses
   `(show-paren-match ((t (:foreground ,bg :background ,omarchy-color-accent :weight bold))))
   `(show-paren-mismatch ((t (:foreground ,bg :background ,omarchy-color-red :weight bold))))

   ;; Completion
   `(completions-common-part ((t (:foreground ,omarchy-color-accent))))
   `(completions-first-difference ((t (:foreground ,fg :weight bold))))

   ;; Links
   `(link ((t (:foreground ,omarchy-color-cyan :underline t))))
   `(link-visited ((t (:foreground ,omarchy-color-magenta :underline t))))

   ;; Errors / warnings
   `(error ((t (:foreground ,omarchy-color-red :weight bold))))
   `(warning ((t (:foreground ,omarchy-color-yellow :weight bold))))
   `(success ((t (:foreground ,omarchy-color-green :weight bold))))

   ;; Org mode
   `(org-level-1 ((t (:foreground ,omarchy-color-blue :weight bold :height 1.1))))
   `(org-level-2 ((t (:foreground ,omarchy-color-magenta :weight bold))))
   `(org-level-3 ((t (:foreground ,omarchy-color-cyan :weight bold))))
   `(org-level-4 ((t (:foreground ,omarchy-color-yellow))))
   `(org-code ((t (:foreground ,omarchy-color-green))))
   `(org-verbatim ((t (:foreground ,omarchy-color-white))))
   `(org-link ((t (:foreground ,omarchy-color-cyan :underline t))))
   `(org-done ((t (:foreground ,omarchy-color-green :weight bold))))
   `(org-todo ((t (:foreground ,omarchy-color-red :weight bold))))

   ;; Diff / ediff
   `(diff-added ((t (:foreground ,omarchy-color-green :background unspecified))))
   `(diff-removed ((t (:foreground ,omarchy-color-red :background unspecified))))
   `(diff-header ((t (:foreground ,omarchy-color-cyan :weight bold))))
   `(diff-file-header ((t (:foreground ,omarchy-color-blue :weight bold))))))

(provide-theme 'omarchy)
;;; omarchy-theme.el ends here
