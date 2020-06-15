(uiop:define-package :nyxt/minibuffer-mode
  (:use :common-lisp :trivia :nyxt)
  (:import-from #:keymap #:define-key #:define-scheme)
  (:import-from #:serapeum #:export-always)
  (:documentation "Mode for minibuffer"))
(in-package :nyxt/minibuffer-mode)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (trivial-package-local-nicknames:add-package-local-nickname :alex :alexandria)
  (trivial-package-local-nicknames:add-package-local-nickname :sera :serapeum))

(define-mode minibuffer-mode ()
  "Mode for the minibuffer."
  ((keymap-scheme
    :initform
    (define-scheme "minibuffer"
      scheme:cua
      (list
       "hyphen" 'self-insert-minibuffer
       "space" 'self-insert-minibuffer
       "C-f" 'cursor-forwards
       "M-f" 'cursor-forwards-word
       "C-right" 'cursor-forwards-word
       "C-b" 'cursor-backwards
       "M-b" 'cursor-backwards-word
       "C-left" 'cursor-backwards-word
       "M-d" 'delete-forwards-word
       "M-backspace" 'delete-backwards-word
       "right" 'cursor-forwards
       "left" 'cursor-backwards
       "C-d" 'delete-forwards
       "delete" 'delete-forwards
       "backspace" 'delete-backwards
       "C-a" 'cursor-beginning
       "home" 'cursor-beginning
       "C-e" 'cursor-end
       "end" 'cursor-end
       "C-k" 'kill-line
       "return" 'return-input
       "C-return" 'return-immediate
       "C-g" 'cancel-input
       "escape" 'cancel-input
       "C-n" 'select-next
       "C-p" 'select-previous
       "M-n" 'select-next-follow
       "M-p" 'select-previous-follow
       "button4" 'select-previous
       "button5" 'select-next
       "down" 'select-next
       "up" 'select-previous
       "C-v" 'minibuffer-paste
       "C-y" 'minibuffer-paste
       "C-w" 'copy-candidate
       "C-c" 'copy-candidate
       "tab" 'insert-candidate
       "M-h" 'minibuffer-history
       "C-space" 'minibuffer-toggle-mark
       "shift-space" 'minibuffer-toggle-mark-backwards
       "M-space" 'minibuffer-toggle-mark
       "M-a" 'minibuffer-mark-all
       "M-u" 'minibuffer-unmark-all))
    ;; TODO: We could have VI bindings for the minibuffer too.
    ;; But we need to make sure it's optional + to have an indicator
    ;; for the mode.
    )))

(define-command return-input (&optional (minibuffer (current-minibuffer)))
  "Return with minibuffer selection."
  (with-slots (nyxt::callback must-match-p nyxt::completions nyxt::completion-cursor
               invisible-input-p
               multi-selection-p nyxt::marked-completions)
      minibuffer
    (match (or nyxt::marked-completions
               (and nyxt::completions
                    (list (nth nyxt::completion-cursor nyxt::completions)))
               (and (not must-match-p)
                    (list (input minibuffer))))
      ((guard nyxt::completions nyxt::completions)
       ;; Note that "immediate input" is also in completions, so it's caught here.
       (setf nyxt::completions
             (mapcar (lambda (completion) (if (stringp completion)
                                              (str:replace-all " " " " completion)
                                              completion))
                     nyxt::completions))
       (funcall-safely nyxt::callback (if multi-selection-p
                                    nyxt::completions
                                    (first nyxt::completions))))
      (nil (when invisible-input-p
             (funcall-safely nyxt::callback (input minibuffer))))))
  (quit-minibuffer minibuffer))

(define-command return-immediate (&optional (minibuffer (current-minibuffer)))
  "Return with minibuffer input, ignoring the selection."
  (with-slots (nyxt::callback) minibuffer
    (funcall-safely nyxt::callback (input minibuffer)))
  (quit-minibuffer minibuffer))

(defun quit-minibuffer (&optional (minibuffer (current-minibuffer)))
  (unless (or (null (history minibuffer))
              (str:empty? (input minibuffer)))
    (containers:insert-item (history minibuffer) (input minibuffer)))
  (cancel-input minibuffer))

(define-command cancel-input (&optional (minibuffer (current-minibuffer)))
  "Close the minibuffer query without further action."
  (match (cleanup-function minibuffer)
    ((guard f f) (funcall-safely f)))
  (hide minibuffer))

(defun self-insert-minibuffer ()
  "Self insert with the current minibuffer."
  (self-insert (nyxt:current-minibuffer)))

(define-command self-insert (receiver)
  "Insert first key from `*browser*' `key-stack' in the minibuffer."
  (let ((key-string (keymap:key-value (first (nyxt::key-stack *browser*))))
        (translation-table '(("hyphen" "-")
                             ;; Regular spaces are concatenated into a single
                             ;; one by HTML rendering, so we use a non-breaking
                             ;; space to avoid confusing the user.
                             ("space" " "))))
    (setf key-string (or (cadr (assoc key-string translation-table :test #'string=))
                         key-string))
    (insert receiver key-string)))

(define-command delete-forwards (&optional (minibuffer (current-minibuffer)))
  "Delete character after cursor."
  (cluffer:delete-item (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command delete-backwards (&optional (minibuffer (current-minibuffer)))
  "Delete character before cursor."
  (text-buffer::delete-item-backward (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command cursor-forwards (&optional (minibuffer (current-minibuffer)))
  "Move cursor forward by one."
  (text-buffer::safe-forward (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command cursor-backwards (&optional (minibuffer (current-minibuffer)))
  "Move cursor backwards by one."
  (text-buffer::safe-backward (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command cursor-beginning (&optional (minibuffer (current-minibuffer)))
  "Move cursor to the beginning of the input area."
  (cluffer:beginning-of-line (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command cursor-end (&optional (minibuffer (current-minibuffer)))
  "Move cursor to the end of the input area."
  (cluffer:end-of-line (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command cursor-forwards-word (&optional (minibuffer (current-minibuffer)))
  "Move cursor to the end of the word at point."
  (text-buffer::move-forward-word (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer)
  (cluffer:cursor-position (input-cursor minibuffer)))

(define-command cursor-backwards-word (&optional (minibuffer (current-minibuffer)))
  "Move cursor to the beginning of the word at point."
  (text-buffer::move-backward-word (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer)
  (cluffer:cursor-position (input-cursor minibuffer)))

(define-command delete-forwards-word (&optional (minibuffer (current-minibuffer)))
  "Delete characters from cursor position until the end of the word at point."
  (text-buffer::delete-forward-word (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command delete-backwards-word (&optional (minibuffer (current-minibuffer)))
  "Delete characters from cursor position until the beginning of the word at point."
  (text-buffer::delete-backward-word (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command kill-line (&optional (minibuffer (current-minibuffer)))
  "Delete all characters from cursor position until the end of the line."
  (text-buffer::kill-forward-line (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command kill-whole-line (&optional (minibuffer (current-minibuffer)))
  "Delete all characters in the input."
  (text-buffer::kill-line (input-cursor minibuffer))
  (state-changed minibuffer)
  (update-display minibuffer))

(define-command select-next (&optional (minibuffer (current-minibuffer)))
  "Select next entry in minibuffer."
  (when (< (nyxt::completion-cursor minibuffer) (- (length (nyxt::completions minibuffer)) 1))
    (incf (nyxt::completion-cursor minibuffer))
    (state-changed minibuffer)
    (update-display minibuffer)
    (evaluate-script minibuffer
                     (ps:ps (ps:chain (ps:chain document (get-element-by-id "selected"))
                                      (scroll-into-view false))))))

(define-command select-previous (&optional (minibuffer (current-minibuffer)))
  "Select previous entry in minibuffer."
  (when (> (nyxt::completion-cursor minibuffer) 0)
    (decf (nyxt::completion-cursor minibuffer))
    (state-changed minibuffer)
    (update-display minibuffer)
    (evaluate-script minibuffer
                     (ps:ps (ps:chain (ps:chain document (get-element-by-id "head"))
                                      (scroll-into-view false))))))

(define-command minibuffer-paste (&optional (minibuffer (current-minibuffer)))
  "Paste clipboard text to input."
  (insert minibuffer (ring-insert-clipboard (nyxt::clipboard-ring *browser*))))

(define-command copy-candidate (&optional (minibuffer (current-minibuffer)))
  "Copy candidate to clipboard."
  (let ((candidate (if (and (multi-selection-p minibuffer)
                            (not (null (nyxt::marked-completions minibuffer))))
                       (str:join (string #\newline) (get-marked-candidates minibuffer))
                       (get-candidate minibuffer))))
    (unless (str:emptyp candidate)
      (trivial-clipboard:text candidate))))

(define-command insert-candidate (&optional (minibuffer (current-minibuffer)))
  "Paste selected candidate to input.
As a special case, if the inserted candidate is a URI, we decode it to make it
readable."
  (let ((candidate (get-candidate minibuffer)))
    (when candidate
      (kill-whole-line minibuffer)
      (insert minibuffer
              (if (valid-url-p candidate)
                  (url-display candidate)
                  candidate)))))

(declaim (ftype (function (containers:ring-buffer-reverse))
                minibuffer-history-completion-filter))
(defun minibuffer-history-completion-filter (history)
  (when history
    (lambda (minibuffer)
      (fuzzy-match (input minibuffer)
                   (delete-duplicates (containers:container->list history)
                                      :test #'equal)))))

(define-command minibuffer-history (&optional (minibuffer (current-minibuffer)))
  "Choose a minibuffer input history entry to insert as input."
  (when (history minibuffer)
    (with-result (input (read-from-minibuffer
                         (make-minibuffer
                          :input-prompt "Input history"
                          :history nil
                          :completion-function (minibuffer-history-completion-filter (history minibuffer)))))
      (unless (str:empty? input)
        (log:debug input minibuffer)
        (text-buffer::kill-line (input-cursor minibuffer))
        (setf (nyxt::input-cursor-position minibuffer) 0)
        (insert minibuffer input)))))

(define-command minibuffer-toggle-mark (&key
                                        (minibuffer (current-minibuffer))
                                        (direction :next))
  "Toggle candidate.
Only available if minibuffer `multi-selection-p' is non-nil.  DIRECTION can be
:next or :previous and specifies which candidate to select once done."
  (when (multi-selection-p minibuffer)
    (with-slots (nyxt::completions nyxt::completion-cursor nyxt::marked-completions) minibuffer
      (let ((candidate (nth nyxt::completion-cursor nyxt::completions)))
        (match (member candidate nyxt::marked-completions)
          ((guard n n) (setf nyxt::marked-completions (delete candidate nyxt::marked-completions)))
          (_ (push candidate nyxt::marked-completions)))))
    (state-changed minibuffer)
    (update-display minibuffer)
    (match direction
      (:next (select-next minibuffer))
      (:previous (select-previous minibuffer)))))

(define-command minibuffer-toggle-mark-backwards (&key (minibuffer (current-minibuffer)))
  "Toggle candidate and select previous candidate.
See `minibuffer-toggle-mark'. "
  (minibuffer-toggle-mark :minibuffer minibuffer :direction :previous))

(define-command minibuffer-mark-all (&optional (minibuffer (current-minibuffer)))
  "Mark all visible candidates.
Only available if minibuffer `multi-selection-p' is non-nil."
  (when (multi-selection-p minibuffer)
    (with-slots (nyxt::completions nyxt::marked-completions) minibuffer
      (setf nyxt::marked-completions (union nyxt::completions nyxt::marked-completions)))
    (state-changed minibuffer)
    (update-display minibuffer)))

(define-command minibuffer-unmark-all (&optional (minibuffer (current-minibuffer)))
  "Unmark all visible candidates.
Only available if minibuffer `multi-selection-p' is non-nil."
  (when (multi-selection-p minibuffer)
    (with-slots (nyxt::completions nyxt::marked-completions) minibuffer
      (setf nyxt::marked-completions (set-difference nyxt::marked-completions nyxt::completions)))
    (state-changed minibuffer)
    (update-display minibuffer)))