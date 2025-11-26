;;; Agent-Zero Cognitive Packages Module
;;; Copyright © 2024 CrystalCog Community
;;;
;;; This file is part of the Agent-Zero cognitive framework.
;;;
;;; This module provides Guix package definitions for the Agent-Zero
;;; cognitive computing framework and related packages.

(define-module (agent-zero packages cognitive)
  #:use-module (gnu packages opencog)
  #:export (opencog
            cogutil
            atomspace
            crystalcog
            guile-pln
            guile-ecan
            guile-moses
            guile-pattern-matcher
            guile-relex
            ggml))

;;; Re-export all packages from (gnu packages opencog)
;;; This provides compatibility with both module structures:
;;; - (gnu packages opencog) - Standard GNU Guix convention
;;; - (agent-zero packages cognitive) - Agent-Zero framework convention
;;;
;;; This allows guix.scm to use (agent-zero packages cognitive) while
;;; maintaining compatibility with standard Guix tooling.
