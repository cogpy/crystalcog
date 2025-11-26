;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2024 OpenCog Community
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages opencog)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix git)
  #:use-module (guix utils)
  #:use-module (guix build-system crystal)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages crystal)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages boost)
  #:use-module (gnu packages pkg-config))

;; Shared source definition for all CrystalCog packages
(define crystalcog-source
  (local-file "../.." "crystalcog-checkout"
              #:recursive? #t
              #:select? (git-predicate (dirname (dirname (current-filename))))))

(define-public cogutil
  (package
    (name "cogutil")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/cogutil/cogutil.cr"))))))
    (synopsis "CrystalCog core utilities library")
    (description
     "CogUtil provides core utilities for CrystalCog including logging,
configuration management, random number generation, and platform utilities.
This is a Crystal language reimplementation of the OpenCog cogutil library.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public atomspace
  (package
    (name "atomspace")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/atomspace/atomspace.cr")))
         (replace 'check
           (lambda _
             (invoke "crystal" "spec" "spec/atomspace"))))))
    (inputs
     (list cogutil sqlite postgresql))
    (synopsis "CrystalCog hypergraph knowledge representation")
    (description
     "AtomSpace is the hypergraph-based knowledge representation system for
CrystalCog. It provides atoms (nodes and links), truth values, attention values,
and a pattern matching query system. This is a Crystal language reimplementation
of the OpenCog AtomSpace.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public opencog
  (package
    (name "opencog")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/opencog/opencog.cr")))
         (replace 'check
           (lambda _
             (invoke "crystal" "spec" "spec/"))))))
    (inputs
     (list atomspace cogutil guile-3.0 sqlite postgresql))
    (synopsis "CrystalCog cognitive computing platform")
    (description
     "CrystalCog is a comprehensive cognitive computing platform implemented in
Crystal language. It includes the AtomSpace hypergraph knowledge representation,
Probabilistic Logic Networks (PLN), Unified Rule Engine (URE), pattern matching,
natural language processing, and evolutionary optimization (MOSES). This is a
complete reimplementation of the OpenCog framework in Crystal.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-pln
  (package
    (name "guile-pln")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/pln/pln.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "Probabilistic Logic Networks for CrystalCog")
    (description
     "PLN (Probabilistic Logic Networks) is an uncertain inference system for
CrystalCog. It provides probabilistic reasoning capabilities including deduction,
induction, abduction, and analogical reasoning.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-ecan
  (package
    (name "guile-ecan")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/attention/attention.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "Economic Attention Networks for CrystalCog")
    (description
     "ECAN (Economic Attention Networks) implements attention allocation
mechanisms for CrystalCog, managing computational resources and focusing
cognitive processing on important knowledge.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-moses
  (package
    (name "guile-moses")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/moses/moses.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "Meta-Optimizing Semantic Evolutionary Search")
    (description
     "MOSES is an evolutionary program learning system for CrystalCog that
uses genetic programming techniques to evolve programs that solve problems.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-pattern-matcher
  (package
    (name "guile-pattern-matcher")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/pattern_matching/pattern_matching_main.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "Advanced pattern matching engine for CrystalCog")
    (description
     "Pattern matching engine for CrystalCog providing sophisticated graph
pattern recognition and query capabilities for the AtomSpace hypergraph.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-relex
  (package
    (name "guile-relex")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/nlp/nlp_main.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "Natural language processing for CrystalCog")
    (description
     "RelEx provides relationship extraction and natural language processing
capabilities for CrystalCog, enabling semantic understanding of text.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public ggml
  (package
    (name "ggml")
    (version "0.1.0")
    (source crystalcog-source)
    (build-system crystal-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (replace 'build
           (lambda _
             (invoke "crystal" "build" "src/ggml/ggml_bindings.cr"))))))
    (inputs
     (list atomspace cogutil))
    (synopsis "GGML tensor library bindings for CrystalCog")
    (description
     "GGML bindings provide efficient tensor operations and machine learning
capabilities for CrystalCog, enabling neural-symbolic integration.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))
;;; Copyright © 2024 OpenCog Community <opencog@googlegroups.com>
;;;
;;; This file is part of CrystalCog.
;;;
;;; CrystalCog is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU Affero General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; CrystalCog is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public License
;;; along with CrystalCog.  If not, see <http://www.gnu.org/licenses/>.

;;; Compatibility module for OpenCog package names
;;; This module re-exports CrystalCog packages with OpenCog-compatible names

(define-module (gnu packages opencog)
  #:use-module (gnu packages crystalcog)
  #:export (crystalcog
            crystalcog-cogutil
            crystalcog-atomspace
            crystalcog-opencog))

;; Re-export CrystalCog packages for compatibility
;; This allows the validation script and existing documentation to work
;; without changes while maintaining the actual package definitions in
;; crystalcog.scm

;; The main packages are defined in (gnu packages crystalcog)
;; and re-exported here for backward compatibility with OpenCog naming
