;;; Agent-Zero Genesis Cognitive Package Module
;;; Copyright © 2024 CrystalCog Contributors
;;;
;;; This file defines Guix packages for the Agent-Zero cognitive architecture
;;;
;;; NOTE: This package file contains placeholder SHA256 hashes (all zeros).
;;; These hashes need to be updated with actual values when CrystalCog
;;; releases are tagged. Use `guix hash -rx /path/to/source` to generate
;;; the correct hash for a specific version or commit.

(define-module (agent-zero packages cognitive)
  #:use-module (gnu packages crystalcog)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system crystal)
  #:use-module (guix build-system guile)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages crystal)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages guile))

;; Re-export the main CrystalCog package
(define-public opencog crystalcog)

;; GGML integration for neural processing
(define-public ggml
  (package
    (name "ggml")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/ggerganov/ggml.git")
                    (commit "master")))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when using a specific commit
                ;; Use: guix hash -rx /path/to/ggml
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (synopsis "Tensor library for machine learning")
    (description
     "GGML is a tensor library for machine learning with focus on
Transformer models, optimized for inference on commodity hardware.")
    (home-page "https://github.com/ggerganov/ggml")
    (license license:expat)))

;; Guile bindings for PLN reasoning
(define-public guile-pln
  (package
    (name "guile-pln")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog.git")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when v0.1.0 release is tagged
                ;; Use: guix hash -rx /path/to/crystalcog
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system guile-build-system)
    (native-inputs
     (list guile-3.0))
    (propagated-inputs
     (list crystalcog-atomspace guile-3.0))
    (synopsis "Guile bindings for Probabilistic Logic Networks")
    (description
     "Guile bindings for CrystalCog's PLN reasoning engine, providing
Scheme-based access to probabilistic inference and reasoning.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

;; Guile bindings for ECAN (Economic Attention Networks)
(define-public guile-ecan
  (package
    (name "guile-ecan")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog.git")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when v0.1.0 release is tagged
                ;; Use: guix hash -rx /path/to/crystalcog
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system guile-build-system)
    (native-inputs
     (list guile-3.0))
    (propagated-inputs
     (list crystalcog-atomspace guile-3.0))
    (synopsis "Guile bindings for Economic Attention Networks")
    (description
     "Guile bindings for CrystalCog's attention allocation mechanisms,
implementing economic models of cognitive resource management.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

;; Guile bindings for MOSES evolutionary optimization
(define-public guile-moses
  (package
    (name "guile-moses")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog.git")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when v0.1.0 release is tagged
                ;; Use: guix hash -rx /path/to/crystalcog
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system guile-build-system)
    (native-inputs
     (list guile-3.0))
    (propagated-inputs
     (list crystalcog guile-3.0))
    (synopsis "Guile bindings for MOSES evolutionary optimization")
    (description
     "Guile bindings for CrystalCog's MOSES (Meta-Optimizing Semantic
Evolutionary Search) framework for program learning.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

;; Guile bindings for pattern matching
(define-public guile-pattern-matcher
  (package
    (name "guile-pattern-matcher")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog.git")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when v0.1.0 release is tagged
                ;; Use: guix hash -rx /path/to/crystalcog
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system guile-build-system)
    (native-inputs
     (list guile-3.0))
    (propagated-inputs
     (list crystalcog-atomspace guile-3.0))
    (synopsis "Guile bindings for CrystalCog pattern matching")
    (description
     "Guile bindings for CrystalCog's advanced pattern matching engine,
providing Scheme-based access to hypergraph pattern queries.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

;; Guile bindings for RelEx natural language processing
(define-public guile-relex
  (package
    (name "guile-relex")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog.git")
                    (commit (string-append "v" version))))
              (file-name (git-file-name name version))
              (sha256
               (base32
                ;; TODO: Update with actual hash when v0.1.0 release is tagged
                ;; Use: guix hash -rx /path/to/crystalcog
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system guile-build-system)
    (native-inputs
     (list guile-3.0))
    (propagated-inputs
     (list crystalcog guile-3.0))
    (synopsis "Guile bindings for natural language processing")
    (description
     "Guile bindings for CrystalCog's natural language processing capabilities,
including semantic parsing and language understanding.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))
