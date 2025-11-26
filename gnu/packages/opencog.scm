;;; GNU Guix --- Functional package management for GNU
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
