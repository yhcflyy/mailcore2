#!/bin/sh

pushd "`dirname "$0"`" > /dev/null
scriptpath="`pwd`"
popd > /dev/null

. "$scriptpath/include.sh/build-dep.sh"

url="https://github.com/dinhviethoa/ctemplate"
rev=d004783679560176f501998fd620f50acfc233f0
name="ctemplate-osx"
xcode_target="ctemplate"
xcode_project="ctemplate.xcodeproj"
library="libctemplate.a"
embedded_deps=""

build_git_osx
