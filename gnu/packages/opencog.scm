;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2024 CrystalCog Community
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
  #:use-module (guix build-system cmake)
  #:use-module (guix build-system gnu)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages boost)
  #:use-module (gnu packages check)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages maths)
  #:use-module (gnu packages perl)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages python-xyz))

(define-public cogutil
  (package
    (name "cogutil")
    (version "2.0.3")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/opencog/cogutil.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system cmake-build-system)
    (arguments
     `(#:configure-flags
       '("-DCMAKE_BUILD_TYPE=Release")))
    (native-inputs
     (list pkg-config))
    (inputs
     (list boost))
    (synopsis "OpenCog utility library")
    (description
     "CogUtil provides low-level C++ utilities used across OpenCog projects.
It includes logging, configuration management, random number generation,
and platform-specific utilities.")
    (home-page "https://github.com/opencog/cogutil")
    (license license:agpl3+)))

(define-public atomspace
  (package
    (name "atomspace")
    (version "5.0.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/opencog/atomspace.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system cmake-build-system)
    (arguments
     `(#:configure-flags
       '("-DCMAKE_BUILD_TYPE=Release"
         "-DENABLE_GUILE=ON"
         "-DENABLE_PYTHON=ON")))
    (native-inputs
     (list pkg-config))
    (inputs
     (list boost
           cogutil
           guile-3.0
           postgresql
           python
           python-cython))
    (synopsis "OpenCog hypergraph database")
    (description
     "AtomSpace is a hypergraph database for knowledge representation.
It provides the core data structures and query system for OpenCog,
implementing a weighted labeled hypergraph with built-in pattern matching
and rule-based inference capabilities.")
    (home-page "https://github.com/opencog/atomspace")
    (license license:agpl3+)))

(define-public opencog
  (package
    (name "opencog")
    (version "5.0.4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/opencog/opencog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system cmake-build-system)
    (arguments
     `(#:configure-flags
       '("-DCMAKE_BUILD_TYPE=Release"
         "-DENABLE_GUILE=ON"
         "-DENABLE_PYTHON=ON")))
    (native-inputs
     (list pkg-config))
    (inputs
     (list atomspace
           boost
           cogutil
           guile-3.0
           python
           python-cython))
    (synopsis "OpenCog cognitive computing platform")
    (description
     "OpenCog is a cognitive computing platform implementing AGI research.
It includes probabilistic logic networks (PLN), the unified rule engine (URE),
pattern matching, natural language processing, evolutionary optimization,
and integration with robotics systems.")
    (home-page "https://opencog.org/")
    (license license:agpl3+)))

(define-public crystalcog
  (package
    (name "crystalcog")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:phases
       (modify-phases %standard-phases
         (delete 'configure)
         (replace 'build
           (lambda _
             (invoke "make" "build")))
         (replace 'check
           (lambda _
             (invoke "make" "test")))
         (replace 'install
           (lambda* (#:key outputs #:allow-other-keys)
             (let ((out (assoc-ref outputs "out")))
               (invoke "make" "install" (string-append "PREFIX=" out))))))))
    (native-inputs
     (list pkg-config))
    (inputs
     (list boost
           guile-3.0
           postgresql))
    (synopsis "Crystal language implementation of OpenCog framework")
    (description
     "CrystalCog is a complete rewrite of the OpenCog artificial intelligence
framework in the Crystal programming language.  It provides better performance,
memory safety, and maintainability while preserving all the functionality of
the original OpenCog system.  Includes implementations of AtomSpace hypergraph
database, Probabilistic Logic Networks (PLN), Unified Rule Engine (URE),
pattern matching, natural language processing, and evolutionary optimization.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

;; Guile bindings and extensions
(define-public guile-pln
  (package
    (name "guile-pln")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:make-flags
       (list (string-append "PREFIX=" (assoc-ref %outputs "out")))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure))))
    (inputs
     (list guile-3.0
           crystalcog))
    (synopsis "Guile bindings for Probabilistic Logic Networks")
    (description
     "Guile-PLN provides Scheme bindings for the Probabilistic Logic Networks
reasoning engine implemented in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-ecan
  (package
    (name "guile-ecan")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:make-flags
       (list (string-append "PREFIX=" (assoc-ref %outputs "out")))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure))))
    (inputs
     (list guile-3.0
           crystalcog))
    (synopsis "Guile bindings for Economic Attention Networks")
    (description
     "Guile-ECAN provides Scheme bindings for the Economic Attention Networks
attention allocation system implemented in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-moses
  (package
    (name "guile-moses")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:make-flags
       (list (string-append "PREFIX=" (assoc-ref %outputs "out")))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure))))
    (inputs
     (list guile-3.0
           crystalcog))
    (synopsis "Guile bindings for MOSES evolutionary optimization")
    (description
     "Guile-MOSES provides Scheme bindings for the Meta-Optimizing Semantic
Evolutionary Search framework implemented in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-pattern-matcher
  (package
    (name "guile-pattern-matcher")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:make-flags
       (list (string-append "PREFIX=" (assoc-ref %outputs "out")))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure))))
    (inputs
     (list guile-3.0
           crystalcog))
    (synopsis "Guile bindings for pattern matching engine")
    (description
     "Guile-Pattern-Matcher provides Scheme bindings for the advanced pattern
matching and mining capabilities implemented in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public guile-relex
  (package
    (name "guile-relex")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/cogpy/crystalcog.git")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system gnu-build-system)
    (arguments
     `(#:make-flags
       (list (string-append "PREFIX=" (assoc-ref %outputs "out")))
       #:phases
       (modify-phases %standard-phases
         (delete 'configure))))
    (inputs
     (list guile-3.0
           crystalcog))
    (synopsis "Guile bindings for RelEx relationship extraction")
    (description
     "Guile-RelEx provides Scheme bindings for the relationship extraction
and natural language processing capabilities implemented in CrystalCog.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public ggml
  (package
    (name "ggml")
    (version "0.1.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/ggerganov/ggml.git")
             (commit "master")))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "0000000000000000000000000000000000000000000000000000"))))
    (build-system cmake-build-system)
    (arguments
     `(#:configure-flags
       '("-DCMAKE_BUILD_TYPE=Release")))
    (synopsis "Tensor library for machine learning")
    (description
     "GGML is a tensor library for machine learning, designed for efficient
inference on CPU.  It provides low-level building blocks for neural networks
and is used for ML integration in CrystalCog.")
    (home-page "https://github.com/ggerganov/ggml")
    (license license:expat)))
