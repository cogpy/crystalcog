;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2024 CrystalCog Contributors
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; NOTE: This package file contains placeholder SHA256 hashes (all zeros).
;;; These hashes need to be updated with actual values when CrystalCog
;;; releases are tagged. Use `guix hash -rx /path/to/crystalcog` to generate
;;; the correct hash for a specific version.

(define-module (gnu packages crystalcog)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system crystal)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages crystal)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages pkg-config))

(define-public crystalcog
  (package
    (name "crystalcog")
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
    (build-system crystal-build-system)
    (arguments
     `(#:tests? #t
       #:phases
       (modify-phases %standard-phases
         (add-before 'build 'install-dependencies
           (lambda _
             (invoke "shards" "install")
             #t)))))
    (native-inputs
     (list crystal pkg-config))
    (inputs
     (list postgresql sqlite))
    (propagated-inputs
     (list crystal))
    (synopsis "Crystal implementation of the OpenCog cognitive architecture")
    (description
     "CrystalCog is a comprehensive rewrite of the OpenCog artificial
intelligence framework in the Crystal programming language.  It provides
better performance, memory safety, and maintainability while preserving all
the functionality of the original OpenCog system.  The framework includes:
@itemize
@item AtomSpace hypergraph knowledge representation
@item Probabilistic Logic Networks (PLN) reasoning
@item Unified Rule Engine (URE)
@item Pattern matching and mining
@item Natural language processing
@item Evolutionary optimization (MOSES)
@item Distributed agent networks
@end itemize")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public crystalcog-cogutil
  (package
    (name "crystalcog-cogutil")
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
    (build-system crystal-build-system)
    (native-inputs
     (list crystal pkg-config))
    (synopsis "Core utilities for CrystalCog")
    (description
     "CogUtil provides core utilities for the CrystalCog cognitive architecture,
including logging, configuration management, and platform utilities.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))

(define-public crystalcog-atomspace
  (package
    (name "crystalcog-atomspace")
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
    (build-system crystal-build-system)
    (native-inputs
     (list crystal pkg-config))
    (inputs
     (list postgresql sqlite))
    (propagated-inputs
     (list crystalcog-cogutil))
    (synopsis "Hypergraph knowledge representation for CrystalCog")
    (description
     "AtomSpace provides a hypergraph-based knowledge representation system
for the CrystalCog cognitive architecture.  It includes pattern matching,
truth values, and persistent storage capabilities.")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))
