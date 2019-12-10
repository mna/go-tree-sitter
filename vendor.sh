#!/bin/bash

# Script to update tree-sitter and grammars

set -e

sitter_version=0.16.1
grammars=(
    "bash;v0.16.0;parser.c;scanner.cc"
    "c-sharp;v0.16.0;parser.c;scanner.c"
    "c;v0.15.3;parser.c"
    "cpp;v0.15.1;parser.c;scanner.cc"
    "go;v0.16.0;parser.c"
    "java;v0.16.0;parser.c"
    "javascript;v0.16.0;parser.c;scanner.c"
    "php;v0.13.1;parser.c;scanner.cc"
    "python;v0.16.0;parser.c;scanner.cc"
    "ruby;v0.16.1;parser.c;scanner.cc"
    "rust;v0.16.0;parser.c;scanner.c"
    "typescript;v0.16.0"
)

function download_sitter() {
    rm -rf vendor
    git clone -b $1 https://github.com/tree-sitter/tree-sitter.git vendor

    sed -i.bak 's/"tree_sitter\//"/g' vendor/lib/src/*.c vendor/lib/src/*.h
    sed -i.bak 's/"unicode\//"/g' vendor/lib/src/unicode/*.h vendor/lib/src/*.h
    # tree-sitter 0.16.1 misses include, might be fixed in newer version
    echo "#include \"language.h\"" | cat - vendor/lib/src/query.c > /tmp/out && mv /tmp/out vendor/lib/src/query.c

    cp vendor/lib/include/tree_sitter/*.h ./
    cp vendor/lib/src/*.c ./
    cp vendor/lib/src/*.h ./
    cp vendor/lib/src/unicode/*.h ./
    rm -rf vendor

    # avoid "duplicate symbols" errors as go compiles all c files separately
    rm ./lib.c
}

function download_grammar() {
    lang=$1; shift
    version=$1; shift
    files=$@
    target=$lang
    if [ "$lang" == "go" ]; then
        target="golang"
    fi
    if [ "$lang" == "c-sharp" ]; then
        target="csharp"
    fi
    mkdir -p "$target"

    echo "downloading $lang $version"
    curl -s -f -S "https://raw.githubusercontent.com/tree-sitter/tree-sitter-$lang/$version/src/tree_sitter/parser.h" -o "$target/parser.h"
    for file in $files; do
        curl -s -f -S "https://raw.githubusercontent.com/tree-sitter/tree-sitter-$lang/$version/src/$file" -o "$target/$file"
        sed -i.bak 's/<tree_sitter\/parser\.h>/"parser\.h"/g' "$target/$file"
        rm "$target/$file.bak"
    done
}

# typescript is special as it contains 2 different grammars
function download_typescript() {
    version=$1; shift
    langs="typescript tsx"
    files="parser.c scanner.c"

    echo "downloading typescript $version"
    for lang in $langs; do
        curl -s -f -S "https://raw.githubusercontent.com/tree-sitter/tree-sitter-typescript/$version/common/scanner.h" -o "typescript/$lang/scanner.h"
        curl -s -f -S "https://raw.githubusercontent.com/tree-sitter/tree-sitter-typescript/$version/$lang/src/tree_sitter/parser.h" -o "typescript/$lang/parser.h"
        for file in $files; do
            curl -s -f -S "https://raw.githubusercontent.com/tree-sitter/tree-sitter-typescript/$version/$lang/src/$file" -o "typescript/$lang/$file"
            sed -i.bak 's/"\.\.\/\.\.\/common\/scanner\.h"/"scanner\.h"/g' "typescript/$lang/$file"
            sed -i.bak 's/<tree_sitter\/parser\.h>/"parser\.h"/g' "typescript/$lang/$file"
        done
        sed -i.bak 's/<tree_sitter\/parser\.h>/"parser\.h"/g' "typescript/$lang/scanner.h"
        rm typescript/$lang/*.bak
    done
}

function download() {
    download_sitter $sitter_version

    for grammar in ${grammars[@]}; do
        if [[ "$grammar" == typescript* ]]; then
            download_typescript `echo $grammar | cut -d';' -f2`
        else
            download_grammar `echo $grammar | tr ';' ' '`
        fi
    done
}

function print_grammar_version() {
    lang=$1
    version=$2
    remote_version=`git ls-remote --tags --refs --sort='-v:refname' "https://github.com/tree-sitter/tree-sitter-$lang.git" v\* | head -n 1 | cut -f2 | cut -d'/' -f3`
    outdated=""
    if [ "$version" != "$remote_version" ]; then
        outdated="outdated"
    fi

    echo -e "$lang\t\tvendored: $version\tremote: $remote_version\t$outdated"
}

function check-updates() {
    remote_version=`git ls-remote --tags --refs --sort='-v:refname' "https://github.com/tree-sitter/tree-sitter.git" | head -n 1 | cut -f2 | cut -d'/' -f3`
    outdated=""
    if [ "$sitter_version" != "$remote_version" ]; then
        outdated="outdated"
    fi
    echo -e "tree-sitter\tvendored: $sitter_version\tremote: $remote_version\t$outdated"

    for grammar in ${grammars[@]}; do
        print_grammar_version `echo $grammar | tr ';' ' '`
    done
}

function tag-grammars() {
    for grammar in ${grammars[@]}; do
        tag-grammar `echo $grammar | tr ';' ' '`
    done
}

function tag-grammar() {
    lang=$1
    version=$2
    if [ "$lang" == "go" ]; then
        lang="golang"
    elif [ "$lang" == "c-sharp" ]; then
        lang="csharp"
    fi
    echo "creating new tag $version for $lang"
    if [[ "$lang" == typescript* ]]; then
        git tag "typescript/typescript/$version" || :
        git tag "typescript/tsx/$version" || :
    else
        # || : means do nothing and return 0 exit code instead of the error
        git tag "$lang/$version" || :
    fi
}

function test-all() {
    go test ./...
    for grammar in ${grammars[@]}; do
        go test github.com/smacker/go-tree-sitter/`echo $grammar | cut -d';' -f1`
    done
}

function help() {
    echo "this script supports following subcommands:"
    echo "* test - runs 'go test' for tree-sitter and each grammar"
    echo "* check-updates - compares vendored versions with remote"
    echo "* download - re-downloads vendored files"
    echo "* tag-grammars - use current commit for new grammar tags"
}

case $1 in
check-updates) check-updates
;;
download) download
;;
tag-grammars) tag-grammars `echo $grammar | tr ';' ' '`
;;
test) test-all
;;
*) help
;;
esac
