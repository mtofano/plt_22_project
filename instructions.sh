#!/bin/sh

# Commands to Run (Mac OSX):

#    Environment Setup Commands:
        
        eval $(opam config env)
        export PATH="/usr/local/Cellar/llvm/9.0.1/bin:$PATH"

#    Run Commands:

        ocamlbuild -pkgs llvm rattle.native
        ./rattle.native -l program-file.rs > example.out
        lli example.out



