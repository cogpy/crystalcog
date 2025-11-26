;; CrystalCog Guix Manifest
;; This file can be used with 'guix environment -m guix.scm'

(use-modules (gnu packages)
             (gnu packages guile)
             (gnu packages maths)
             (gnu packages pkg-config)
             (gnu packages boost)
             (gnu packages cmake)
             (gnu packages gcc)
             (gnu packages opencog))
             (gnu packages crystalcog)
             (gnu packages crystal)
             (gnu packages databases)
             (gnu packages pkg-config))

(packages->manifest
  (list
    ;; Core Crystal
    crystal
    
    ;; Build tools
    pkg-config
    
    ;; CrystalCog packages
    crystalcog
    crystalcog-cogutil
    crystalcog-atomspace
    crystalcog-opencog
    
    ;; Database backends
    sqlite
    postgresql))
