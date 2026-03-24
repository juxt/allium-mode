;;; allium-mode-core-test.el --- Core tests for allium-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for core allium-mode behavior that does not require an LSP client.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'imenu)
(load (expand-file-name "allium-mode-test-helpers" (file-name-directory (or load-file-name buffer-file-name))) nil 'nomessage)

(ert-deftest allium-mode-sets-core-buffer-locals ()
  "allium-mode configures expected editor-local defaults."
  (allium-test-load-mode)
  (with-temp-buffer
    (allium-mode)
    (should (eq major-mode 'allium-mode))
    (should (equal comment-start "-- "))
    (should (equal comment-end ""))
    (should (eq indent-line-function #'allium-indent-line))
    (should (equal font-lock-defaults '(allium-font-lock-keywords)))
    (should (equal allium-indent-offset 4))))

(ert-deftest allium-mode-registers-file-extension ()
  "\.allium files are mapped to allium-mode."
  (allium-test-load-mode)
  (let ((mode (assoc-default "sample.allium" auto-mode-alist #'string-match)))
    (should (eq mode 'allium-mode))))

(ert-deftest allium-mode-indents-block-content-and-closing-braces ()
  "Indentation follows block structure around braces."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nwhen: Trigger()\nensures: Done()\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat
                    "rule A {\n"
                    "    when: Trigger()\n"
                    "    ensures: Done()\n"
                    "}\n")))))

(ert-deftest allium-mode-indentation-respects-custom-indent-offset ()
  "Indentation should use `allium-indent-offset` when opening/closing blocks."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nwhen: Trigger()\n}\n")
    (allium-mode)
    (let ((allium-indent-offset 2))
      (indent-region (point-min) (point-max)))
    (should (equal (buffer-string)
                   (concat
                    "rule A {\n"
                    "  when: Trigger()\n"
                    "}\n")))))

(ert-deftest allium-mode-recognizes-line-comments-with-double-dash ()
  "Syntax table should treat `--` as a line comment delimiter."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "-- hello\nrule A {\n}\n")
    (allium-mode)
    (goto-char (point-min))
    (search-forward "hello")
    (should (nth 4 (syntax-ppss)))))

(ert-deftest allium-mode-applies-font-lock-faces-for-key-parts ()
  "Regex font-lock should highlight declarations, clauses, and field keys."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule Ping {\n  when: Trigger()\n  ensures: Done()\n}\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "rule")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face))
    (search-forward "Ping")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-type-face))
    (search-forward "when:")
    (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-keyword-face))
    (search-forward "ensures:")
    (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-keyword-face))))

(ert-deftest allium-mode-configures-treesit-when-grammar-is-ready ()
  "allium-mode should configure tree-sitter locals when parser can be created."
  (allium-test-load-mode)
  (let (parser-language setup-called)
    (cl-letf (((symbol-function 'treesit-parser-create)
               (lambda (lang) (setq parser-language lang)))
              ((symbol-function 'treesit-major-mode-setup)
               (lambda () (setq setup-called t))))
      (with-temp-buffer
        (allium-mode)
        (should (eq parser-language 'allium))
        (should (equal treesit-font-lock-settings allium--treesit-font-lock-rules))
        (should (equal treesit-defun-type-regexp allium--treesit-defun-type-regexp))
        (should (eq treesit-defun-name-function #'allium--treesit-defun-name))
        (should (equal treesit-simple-imenu-settings allium--treesit-imenu-settings))
        (should setup-called)))))

(ert-deftest allium-mode-skips-treesit-setup-when-parser-creation-fails ()
  "allium-mode should fall back to regex font-lock when parser creation fails."
  (allium-test-load-mode)
  (let (setup-called)
    (cl-letf (((symbol-function 'treesit-parser-create)
               (lambda (_lang) (error "parser unavailable")))
              ((symbol-function 'treesit-major-mode-setup)
               (lambda () (setq setup-called t))))
      (with-temp-buffer
        (allium-mode)
        (should (eq major-mode 'allium-mode))
        (should-not (local-variable-p 'treesit-font-lock-settings))
        (should-not setup-called)))))

(ert-deftest allium-mode-imenu-settings-wired-when-treesit-active ()
  "When tree-sitter activates, imenu settings should match all declaration node types."
  (allium-test-load-mode)
  (cl-letf (((symbol-function 'treesit-parser-create)
             (lambda (_lang) nil))
            ((symbol-function 'treesit-major-mode-setup)
             (lambda () nil)))
    (with-temp-buffer
      (allium-mode)
      (let ((settings treesit-simple-imenu-settings))
        (should settings)
        ;; Every expected declaration node type should be matched by at least one entry.
        (dolist (node-type '("rule_declaration" "entity_declaration"
                             "external_entity_declaration" "value_declaration"
                             "enum_declaration" "config_block"
                             "contract_declaration" "invariant_declaration"))
          (should (cl-some (lambda (entry)
                             (string-match-p (nth 1 entry) node-type))
                           settings)))))))

(ert-deftest allium-mode-sets-ts-mode-name-when-grammar-available ()
  "When tree-sitter parser creation succeeds, mode-name should be Allium[TS]."
  (allium-test-load-mode)
  (cl-letf (((symbol-function 'treesit-parser-create)
             (lambda (_lang) nil))
            ((symbol-function 'treesit-major-mode-setup)
             (lambda () nil)))
    (with-temp-buffer
      (allium-mode)
      (should (equal mode-name "Allium[TS]")))))

(ert-deftest allium-treesit-defun-name-supports-context-and-config-nodes ()
  "allium--treesit-defun-name should map anonymous block node types to labels."
  (allium-test-load-mode)
  (cl-letf (((symbol-function 'treesit-node-type) (lambda (node) node)))
    (should (equal (allium--treesit-defun-name "config_block") "config"))))

(ert-deftest allium-treesit-defun-name-reads-declaration-name-field ()
  "allium--treesit-defun-name should read the name field for declarations."
  (allium-test-load-mode)
  (cl-letf (((symbol-function 'treesit-node-type) (lambda (_node) "default_declaration"))
            ((symbol-function 'treesit-node-child-by-field-name)
             (lambda (_node field-name) field-name))
            ((symbol-function 'treesit-node-text)
             (lambda (node _with-properties) (format "name-from-%s" node))))
    (should (equal (allium--treesit-defun-name 'fake-node) "name-from-name"))))

;;; --- Indentation with v3 constructs ---

(ert-deftest allium-mode-indents-transition-block ()
  "Transition block edges should indent inside the braces."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "transitions status {\ndraft -> active\nactive -> closed\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat
                    "transitions status {\n"
                    "    draft -> active\n"
                    "    active -> closed\n"
                    "}\n")))))

(ert-deftest allium-mode-indents-for-block-body ()
  "Body of a `for x in items:` should not change indent (no braces)."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nfor x in items:\nprocess(x)\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat
                    "rule A {\n"
                    "    for x in items:\n"
                    "    process(x)\n"
                    "}\n")))))

(ert-deftest allium-mode-indents-if-block-body ()
  "Body following `if condition:` stays at the same level (no braces)."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nif active:\ndo_thing()\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string)
                   (concat
                    "rule A {\n"
                    "    if active:\n"
                    "    do_thing()\n"
                    "}\n")))))

(ert-deftest allium-mode-indents-nested-blocks ()
  "An entity containing a transition block should indent both levels."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "entity Ticket {\nid: String\ntransitions status {\ndraft -> active\n}\n}\n")
    (allium-mode)
    (let ((indent-tabs-mode nil))
      (indent-region (point-min) (point-max)))
    (should (equal (buffer-string)
                   (concat
                    "entity Ticket {\n"
                    "    id: String\n"
                    "    transitions status {\n"
                    "        draft -> active\n"
                    "    }\n"
                    "}\n")))))

;;; --- Font-lock for v3 keywords ---

(ert-deftest allium-mode-fontifies-v3-keywords ()
  "v3 keywords should receive keyword face via regex font-lock."
  (allium-test-load-mode)
  (dolist (kw '("for" "in" "if" "else" "where" "with" "exists" "transitions" "terminal"))
    (with-temp-buffer
      (insert (concat kw " something\n"))
      (allium-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward kw)
      (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face)))))

(ert-deftest allium-mode-fontifies-backtick-literals ()
  "Backtick-delimited literals should get string face."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "`hello world`\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "hello")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-string-face))))

(ert-deftest allium-mode-fontifies-context-clause-keyword ()
  "`context:` should receive keyword face as a clause keyword."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "context: SomeCtx\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "context:")
    ;; The colon-bearing clause keyword regex highlights up to the colon.
    ;; Check that the "t" in "context" (just before the colon) has keyword face.
    (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-keyword-face))))

;;; --- Comment handling ---

(ert-deftest allium-mode-comment-region-inserts-double-dash ()
  "`comment-region` should prepend `-- ` to each line."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "alpha\nbeta\n")
    (allium-mode)
    (comment-region (point-min) (point-max))
    (should (string-match-p "^-- alpha" (buffer-string)))
    (should (string-match-p "^-- beta" (buffer-string)))))

(ert-deftest allium-mode-uncomment-region-removes-double-dash ()
  "`uncomment-region` should strip `-- ` prefixes."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "-- alpha\n-- beta\n")
    (allium-mode)
    (uncomment-region (point-min) (point-max))
    (should (equal (buffer-string) "alpha\nbeta\n"))))

(ert-deftest allium-mode-comment-syntax-in-multiline-block ()
  "A `--` comment inside a block body should be recognised as a comment."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\n  -- a comment\n  when: Trigger()\n}\n")
    (allium-mode)
    (goto-char (point-min))
    (search-forward "a comment")
    (should (nth 4 (syntax-ppss)))))

;;; --- Defun navigation ---

(ert-deftest allium-mode-defun-type-regexp-matches-all-declaration-types ()
  "The defun type regexp should match every expected declaration node type."
  (allium-test-load-mode)
  (let ((expected '("rule_declaration"
                    "entity_declaration"
                    "external_entity_declaration"
                    "value_declaration"
                    "enum_declaration"
                    "surface_declaration"
                    "actor_declaration"
                    "config_block"
                    "default_declaration"
                    "variant_declaration"
                    "contract_declaration"
                    "invariant_declaration")))
    (dolist (type expected)
      (should (string-match-p allium--treesit-defun-type-regexp type)))))

(ert-deftest allium-mode-defun-type-regexp-rejects-non-declaration-types ()
  "The defun type regexp should not match non-declaration node types."
  (allium-test-load-mode)
  (let ((non-types '("comment"
                     "field_assignment"
                     "identifier"
                     "string_literal"
                     "clause_keyword"
                     "for_block"
                     "transition_block")))
    (dolist (type non-types)
      (should-not (string-match-p allium--treesit-defun-type-regexp type)))))

;;; --- Imenu settings ---

(ert-deftest allium-mode-imenu-settings-cover-expected-categories ()
  "Imenu settings should include entries for all expected declaration categories."
  (allium-test-load-mode)
  (let ((categories (mapcar #'car allium--treesit-imenu-settings)))
    (dolist (cat '("Rule" "Entity" "Value" "Enum" "Config" "Contract" "Invariant"))
      (should (member cat categories)))))

(ert-deftest allium-mode-imenu-settings-entity-matches-both-entity-types ()
  "The Entity imenu entry should match both entity and external_entity declarations."
  (allium-test-load-mode)
  (let* ((entity-entry (cl-find "Entity" allium--treesit-imenu-settings
                                :key #'car :test #'equal))
         (pattern (nth 1 entity-entry)))
    (should (string-match-p pattern "entity_declaration"))
    (should (string-match-p pattern "external_entity_declaration"))))

;;; --- Font-lock edge cases ---

(ert-deftest allium-mode-fontifies-declaration-name-as-type ()
  "Declaration names following a keyword should get type face."
  (allium-test-load-mode)
  (dolist (kw '("rule" "entity" "value" "enum" "surface" "actor"
                "variant" "contract" "invariant"))
    (with-temp-buffer
      (insert (concat kw " MyThing {\n}\n"))
      (allium-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward "MyThing")
      (should (eq (get-text-property (1- (point)) 'face) 'font-lock-type-face)))))

(ert-deftest allium-mode-fontifies-annotations-as-keyword ()
  "Annotations like @invariant, @guidance and @guarantee should get keyword face."
  (allium-test-load-mode)
  (dolist (ann '("@invariant" "@guidance" "@guarantee"))
    (with-temp-buffer
      (insert (concat ann " some_ref\n"))
      (allium-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward ann)
      (should (eq (get-text-property (1- (point)) 'face) 'font-lock-keyword-face)))))

(ert-deftest allium-mode-fontifies-clause-keywords-with-colons ()
  "Clause keywords followed by a colon should get keyword face."
  (allium-test-load-mode)
  (dolist (kw '("when" "requires" "ensures"))
    (with-temp-buffer
      (insert (concat kw ": Something()\n"))
      (allium-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward (concat kw ":"))
      ;; Check the last letter of the keyword (just before the colon).
      (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-keyword-face)))))

(ert-deftest allium-mode-fontifies-string-literals ()
  "Double-quoted string literals should get string face via syntactic fontification."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "name: \"hello world\"\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "hello")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-string-face))))

(ert-deftest allium-mode-fontifies-numbers-as-constant ()
  "Numeric literals should get constant face."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "count: 42\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "42")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-constant-face))))

(ert-deftest allium-mode-fontifies-boolean-and-null-as-constant ()
  "true, false and null should get constant face."
  (allium-test-load-mode)
  (dolist (lit '("true" "false" "null"))
    (with-temp-buffer
      (insert (concat "val: " lit "\n"))
      (allium-mode)
      (font-lock-ensure)
      (goto-char (point-min))
      (search-forward lit)
      (should (eq (get-text-property (1- (point)) 'face) 'font-lock-constant-face)))))

(ert-deftest allium-mode-fontifies-field-assignment-key-as-variable-name ()
  "Field assignment keys should get variable-name face."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "entity Ticket {\n  name: String\n}\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "name:")
    ;; "name" is group 1 of the field assignment pattern.
    (should (eq (get-text-property (- (point) 2) 'face) 'font-lock-variable-name-face))))

(ert-deftest allium-mode-fontifies-duration-literal-as-constant ()
  "Duration literals like 5.minutes should get constant face."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "timeout: 5.minutes\n")
    (allium-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "5.minutes")
    (should (eq (get-text-property (1- (point)) 'face) 'font-lock-constant-face))))

;;; --- Indentation edge cases ---

(ert-deftest allium-mode-indents-triple-nested-braces ()
  "Three levels of brace nesting should produce three levels of indentation."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "entity Org {\nteams: List {\ninner {\nfield: Val\n}\n}\n}\n")
    (allium-mode)
    (let ((indent-tabs-mode nil))
      (indent-region (point-min) (point-max)))
    (should (equal (buffer-string)
                   (concat
                    "entity Org {\n"
                    "    teams: List {\n"
                    "        inner {\n"
                    "            field: Val\n"
                    "        }\n"
                    "    }\n"
                    "}\n")))))

(ert-deftest allium-mode-closing-brace-deindents ()
  "A closing brace on its own line should de-indent by one level."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nwhen: Trigger()\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (forward-line 2)
    (should (= (current-indentation) 0))))

(ert-deftest allium-mode-top-level-has-no-indent ()
  "Top-level lines should have zero indentation."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\n}\nrule B {\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (should (= (current-indentation) 0))
    (forward-line 2)
    (should (= (current-indentation) 0))))

(ert-deftest allium-mode-non-block-line-keeps-indent ()
  "A line following a non-block-opening line should stay at the same indent."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "rule A {\nalpha()\nbeta()\n}\n")
    (allium-mode)
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (forward-line 1)
    (should (= (current-indentation) 4))
    (forward-line 1)
    (should (= (current-indentation) 4))))

(ert-deftest allium-mode-empty-buffer-indentation ()
  "Indenting an empty buffer should not signal an error."
  (allium-test-load-mode)
  (with-temp-buffer
    (allium-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) ""))))

;;; --- Syntax table edge cases ---

(ert-deftest allium-mode-syntax-ppss-recognises-strings ()
  "syntax-ppss should report that point inside a string is in string state."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "name: \"inside string\"\n")
    (allium-mode)
    (goto-char (point-min))
    (search-forward "inside")
    (should (nth 3 (syntax-ppss)))))

(ert-deftest allium-mode-unterminated-string-does-not-break-subsequent-syntax ()
  "An unterminated string should not prevent syntax analysis of later lines."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "broken: \"no end\nrule A {\n}\n")
    (allium-mode)
    ;; The key property: the buffer should still be parseable without error.
    ;; Point on the last line should not signal.
    (goto-char (point-max))
    (should (listp (syntax-ppss)))))

(ert-deftest allium-mode-double-dash-is-comment-single-dash-is-not ()
  "`--` starts a comment, but a lone `-` should not be in comment state."
  (allium-test-load-mode)
  (with-temp-buffer
    (insert "-- comment\na - b\n")
    (allium-mode)
    (goto-char (point-min))
    (search-forward "comment")
    (should (nth 4 (syntax-ppss)))
    (search-forward "a - b")
    (goto-char (- (point) 2))
    (should-not (nth 4 (syntax-ppss)))))

;;; --- Mode setup ---

(ert-deftest allium-mode-derives-from-prog-mode ()
  "allium-mode should be a child of prog-mode."
  (allium-test-load-mode)
  (with-temp-buffer
    (allium-mode)
    (should (derived-mode-p 'prog-mode))))

(ert-deftest allium-mode-auto-mode-alist-regexp ()
  "The auto-mode-alist entry should match .allium files correctly."
  (allium-test-load-mode)
  (let ((entry (cl-find 'allium-mode auto-mode-alist :key #'cdr)))
    (should entry)
    (should (string-match-p (car entry) "spec.allium"))
    (should (string-match-p (car entry) "/path/to/file.allium"))
    (should-not (string-match-p (car entry) "file.alliumx"))
    (should-not (string-match-p (car entry) "file.txt"))))

;;; --- LSP registration completeness ---

(ert-deftest allium-mode-eglot-registers-mode ()
  "eglot registration should cover allium-mode."
  (allium-test-reset-environment)
  (setq eglot-server-programs nil)
  (provide 'eglot)
  (unwind-protect
      (progn
        (allium-test-load-mode t)
        (should (alist-get 'allium-mode eglot-server-programs)))
    (allium-test-reset-environment)))

(ert-deftest allium-mode-lsp-mode-registers-mode ()
  "lsp-mode language-id configuration should cover allium-mode."
  (allium-test-reset-environment)
  (let (registered-client)
    (cl-letf (((symbol-function 'lsp-register-client)
               (lambda (client) (setq registered-client client)))
              ((symbol-function 'make-lsp-client)
               (lambda (&rest plist) plist))
              ((symbol-function 'lsp-stdio-connection)
               (lambda (command-fn) (funcall command-fn))))
      (provide 'lsp-mode)
      (unwind-protect
          (progn
            (allium-test-load-mode t)
            (should (equal (alist-get 'allium-mode lsp-language-id-configuration) "allium")))
        (allium-test-reset-environment)))))

(ert-deftest allium-mode-lsp-mode-language-id-is-allium ()
  "lsp-mode client registration should use language-id \"allium\"."
  (allium-test-reset-environment)
  (let (registered-client)
    (cl-letf (((symbol-function 'lsp-register-client)
               (lambda (client) (setq registered-client client)))
              ((symbol-function 'make-lsp-client)
               (lambda (&rest plist) plist))
              ((symbol-function 'lsp-stdio-connection)
               (lambda (command-fn) (funcall command-fn))))
      (provide 'lsp-mode)
      (unwind-protect
          (progn
            (allium-test-load-mode t)
            (should registered-client)
            (should (equal (plist-get registered-client :language-id) "allium"))
            (should (equal (plist-get registered-client :major-modes)
                           '(allium-mode))))
        (allium-test-reset-environment)))))

(provide 'allium-mode-core-test)
;;; allium-mode-core-test.el ends here
