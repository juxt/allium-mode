;;; allium-mode-core-test.el --- Core tests for allium-mode -*- lexical-binding: t; -*-

;;; Commentary:

;; Unit tests for core allium-mode behavior that does not require an LSP client.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'imenu)
(require 'allium-mode-test-helpers)

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

(ert-deftest allium-ts-mode-is-selectable-without-grammar-install ()
  "allium-ts-mode should still activate even if grammar is unavailable."
  (allium-test-load-mode)
  (with-temp-buffer
    (allium-ts-mode)
    (should (eq major-mode 'allium-ts-mode))))

(ert-deftest allium-ts-mode-configures-treesit-when-grammar-is-ready ()
  "allium-ts-mode should configure tree-sitter locals when parser can be created."
  (allium-test-load-mode)
  (let (parser-language setup-called)
    (cl-letf (((symbol-function 'treesit-parser-create)
               (lambda (lang) (setq parser-language lang)))
              ((symbol-function 'treesit-major-mode-setup)
               (lambda () (setq setup-called t))))
      (with-temp-buffer
        (allium-ts-mode)
        (should (eq parser-language 'allium))
        (should (equal treesit-font-lock-settings allium--treesit-font-lock-rules))
        (should (equal treesit-defun-type-regexp allium--treesit-defun-type-regexp))
        (should (eq treesit-defun-name-function #'allium--treesit-defun-name))
        (should (equal treesit-simple-imenu-settings allium--treesit-imenu-settings))
        (should setup-called)))))

(ert-deftest allium-ts-mode-skips-treesit-setup-when-parser-creation-fails ()
  "allium-ts-mode should stay active even when parser creation signals an error."
  (allium-test-load-mode)
  (let (setup-called)
    (cl-letf (((symbol-function 'treesit-parser-create)
               (lambda (_lang) (error "parser unavailable")))
              ((symbol-function 'treesit-major-mode-setup)
               (lambda () (setq setup-called t))))
      (with-temp-buffer
        (allium-ts-mode)
        (should (eq major-mode 'allium-ts-mode))
        (should-not (local-variable-p 'treesit-font-lock-settings))
        (should-not setup-called)))))

(ert-deftest allium-ts-mode-imenu-lists-top-level-declarations-with-repo-grammar ()
  "With the repo grammar built, imenu should include top-level declaration names."
  (allium-test-load-mode)
  (unless (and (file-directory-p allium-test--treesit-lib-dir)
               (fboundp 'treesit-parser-create))
    (ert-skip "tree-sitter parser setup unavailable"))
  (unless (fboundp 'treesit-major-mode-setup)
    (ert-skip "treesit major-mode imenu wiring unavailable in this Emacs build"))
  (with-temp-buffer
    (insert "entity Ticket {\n  id: String\n}\n\nrule Close {\n  when: Trigger()\n  ensures: Done()\n}\n")
    (allium-ts-mode)
    (let ((index (imenu--make-index-alist t)))
      (should (string-match-p "Ticket" (format "%S" index)))
      (should (string-match-p "Close" (format "%S" index))))))

(ert-deftest allium-ts-mode-uses-real-tree-sitter-grammar-when-installed ()
  "When grammar artifacts exist, Emacs should create an allium parser from them."
  (allium-test-load-mode)
  (unless (file-directory-p allium-test--treesit-lib-dir)
    (ert-skip "local tree-sitter grammar directory is unavailable"))
  (unless (fboundp 'treesit-parser-create)
    (ert-skip "tree-sitter parser APIs are unavailable in this Emacs build"))
  (with-temp-buffer
    (insert "rule A {\n  when: Trigger()\n  ensures: Done()\n}\n")
    (allium-mode)
    (should-not (condition-case nil
                    (progn (treesit-parser-create 'allium) nil)
                  (error t)))
    (should (> (length (treesit-parser-list)) 0))))

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

(provide 'allium-mode-core-test)
;;; allium-mode-core-test.el ends here
