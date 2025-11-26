;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2025 CrystalCog Contributors
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.

(define-module (gnu packages opencog)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system crystal)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages databases)
  #:use-module (gnu packages pkg-config))

(define-public crystalcog
  (package
    (name "crystalcog")
    (version "0.1.0")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                    (url "https://github.com/cogpy/crystalcog")
                    (commit "main")))
              (file-name (git-file-name name version))
              (sha256
               (base32
                "0000000000000000000000000000000000000000000000000000"))))
    (build-system crystal-build-system)
    (arguments
     `(#:tests? #t
       #:shards-file "shard.yml"))
    (native-inputs
     (list pkg-config))
    (inputs
     (list sqlite postgresql))
    (synopsis "OpenCog artificial intelligence framework in Crystal")
    (description
     "CrystalCog is a comprehensive rewrite of the OpenCog artificial
intelligence framework in the Crystal programming language.  It provides
better performance, memory safety, and maintainability while preserving
all the functionality of the original OpenCog system.

Features include:
@itemize
@item AtomSpace hypergraph knowledge representation
@item Probabilistic Logic Networks (PLN) reasoning
@item Unified Rule Engine (URE)
@item Pattern matching and mining
@item Natural language processing
@item Distributed agent systems
@item Performance profiling and optimization tools
@end itemize")
    (home-page "https://github.com/cogpy/crystalcog")
    (license license:agpl3+)))
