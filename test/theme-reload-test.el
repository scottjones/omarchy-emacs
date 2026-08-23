;;; theme-reload-test.el --- Theme reload tests -*- lexical-binding: t -*-

(require 'ert)
(require 'cl-lib)
(require 'server)

;;; Code:

(declare-function omarchy-apply-theme "../config/omarchy")

(defconst omarchy-test-root
  (file-name-directory (directory-file-name
                        (file-name-directory (or load-file-name buffer-file-name)))))

(defun omarchy-test-write-colors (file background foreground)
  "Write a complete generated palette to FILE using BACKGROUND and FOREGROUND."
  (with-temp-file file
    (insert ";;; -*- lexical-binding: t -*-\n")
    (dolist (variable '(omarchy-color-accent omarchy-color-cursor
                        omarchy-color-sel-fg omarchy-color-sel-bg
                        omarchy-color-black omarchy-color-red
                        omarchy-color-green omarchy-color-yellow
                        omarchy-color-blue omarchy-color-magenta
                        omarchy-color-cyan omarchy-color-white
                        omarchy-color-bright-black omarchy-color-bright-red
                        omarchy-color-bright-green omarchy-color-bright-yellow
                        omarchy-color-bright-blue omarchy-color-bright-magenta
                        omarchy-color-bright-cyan omarchy-color-bright-white))
      (prin1 `(setq ,variable "#778899") (current-buffer))
      (insert "\n"))
    (prin1 `(setq omarchy-color-bg ,background
                  omarchy-color-fg ,foreground)
           (current-buffer))
    (insert "\n(provide 'omarchy-colors)\n")))

(ert-deftest omarchy-theme-reload-keeps-incoming-default-colors ()
  (let* ((home (make-temp-file "omarchy-emacs-test-" t))
         (process-environment (copy-sequence process-environment))
         (default-directory omarchy-test-root)
         (user-emacs-directory (expand-file-name ".config/emacs/" home))
         (state (expand-file-name ".local/state/omarchy/current/" home))
         (theme-directory (expand-file-name "theme/" state))
         (colors-file (expand-file-name "omarchy-colors.el" theme-directory))
         (theme-file (expand-file-name "themes/omarchy-theme.el"
                                       user-emacs-directory))
         (new-background "#223344")
         (new-foreground "#ddeeff")
         observed)
    (unwind-protect
        (progn
          (setenv "HOME" home)
          (make-directory theme-directory t)
          (make-directory (file-name-directory theme-file) t)
          (copy-file (expand-file-name "config/themes/omarchy-theme.el"
                                      omarchy-test-root)
                     theme-file)
          (omarchy-test-write-colors colors-file "#111111" "#eeeeee")
          (with-temp-file (expand-file-name "theme.name" state)
            (insert "first\n"))
          (cl-letf (((symbol-function 'server-running-p) (lambda () t))
                    ((symbol-function 'server-start) #'ignore)
                    ((symbol-function 'executable-find) (lambda (_name) nil)))
            (load (expand-file-name "config/omarchy.el" omarchy-test-root)
                  nil 'nomessage))
          (omarchy-test-write-colors colors-file new-background new-foreground)
          (cl-labels ((capture (theme)
                        (when (eq theme 'omarchy)
                          (setq observed
                                (list (face-attribute 'default :background nil t)
                                      (face-attribute 'default :foreground nil t)
                                      (frame-parameter nil 'background-color)
                                      (frame-parameter nil 'foreground-color))))))
            (advice-add 'disable-theme :after #'capture)
            (unwind-protect (omarchy-apply-theme)
              (advice-remove 'disable-theme #'capture)))
          (should (equal observed
                         (list new-background new-foreground
                               new-background new-foreground))))
      (delete-directory home t))))

;;; theme-reload-test.el ends here
