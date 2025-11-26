;;; GNU Guix package definitions for CrystalCog and Agent-Zero
;;; Copyright © 2024 CrystalCog Project
;;;
;;; This file is part of the CrystalCog project.

(define-module (agent-zero packages cognitive)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages boost)
  #:use-module (gnu packages cmake)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages llvm)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages version-control))

;; Note: These package definitions are placeholders for CrystalCog
;; development environment setup. Until Guix has native Crystal build
;; system support, we define these as stubs to enable the manifest to load.
;; The SHA256 hashes are dummy values since builds are deleted in the
;; arguments phase - these packages are not actually built by Guix.

(define-public opencog
  (package
    (name "opencog")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                ;; Dummy hash - package build phases are deleted
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (synopsis "CrystalCog cognitive architecture")
    (description
     "CrystalCog is a comprehensive rewrite of the OpenCog artificial
intelligence framework in the Crystal programming language.  This package
provides the core cognitive architecture with reasoning engines, AtomSpace
hypergraph database, and AI subsystems.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public ggml
  (package
    (name "ggml")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (synopsis "GGML tensor library for CrystalCog")
    (description
     "GGML tensor library integration for machine learning in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:mit)))

(define-public guile-pln
  (package
    (name "guile-pln")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (native-inputs (list guile-3.0))
    (synopsis "Probabilistic Logic Networks for Guile")
    (description
     "Guile bindings for CrystalCog's Probabilistic Logic Networks (PLN)
reasoning engine.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-ecan
  (package
    (name "guile-ecan")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (native-inputs (list guile-3.0))
    (synopsis "Economic Attention Networks for Guile")
    (description
     "Guile bindings for CrystalCog's Economic Attention Network (ECAN)
attention allocation system.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-moses
  (package
    (name "guile-moses")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (native-inputs (list guile-3.0))
    (synopsis "MOSES evolutionary learning for Guile")
    (description
     "Guile bindings for CrystalCog's Meta-Optimizing Semantic Evolutionary
Search (MOSES) system.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-pattern-matcher
  (package
    (name "guile-pattern-matcher")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (native-inputs (list guile-3.0))
    (synopsis "Pattern matching engine for Guile")
    (description
     "Guile bindings for CrystalCog's advanced pattern matching engine.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-relex
  (package
    (name "guile-relex")
    (version "0.1.0")
    (source (origin
              (method url-fetch)
              (uri "https://github.com/cogpy/crystalcog/archive/refs/heads/main.tar.gz")
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     '(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (delete 'build)
         (delete 'check)
         (delete 'install))))
    (native-inputs (list guile-3.0))
    (synopsis "RelEx natural language processing for Guile")
    (description
     "Guile bindings for CrystalCog's RelEx natural language processing system.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))
