#!/bin/sh

if test "x$scriptpath" = x ; then
  case "$0" in
    */include.sh/*) scriptpath="`cd "$(dirname "$0")/.." && pwd`" ;;
    *) scriptpath="`cd "$(dirname "$0")" && pwd`" ;;
  esac
fi

# Map packaged iOS dependency name -> local source tree under deps/
local_dep_src_dir()
{
  case "$1" in
    ctemplate-ios) echo "$scriptpath/../deps/ctemplate" ;;
    libetpan-ios) echo "$scriptpath/../deps/libetpan" ;;
    tidy-html5-ios) echo "$scriptpath/../deps/tidy-html5" ;;
    *) echo "" ;;
  esac
}

fix_tidy_include_layout()
{
  _base="$1"
  _srcdir="$2"
  if test ! -d "$_base/include" && test -n "$_srcdir" && test -d "$_srcdir/include" ; then
    mkdir -p "$_base/include"
    cp -R "$_srcdir/include/"* "$_base/include/"
  fi
  if test -d "$_base/include/tidy" ; then
    cp "$_base/include/tidy/"*.h "$_base/include/" 2>/dev/null || true
  fi
}

patch_dep_sources()
{
  _root="$1"
  for _proj in "$_root/build-mac/ctemplate.xcodeproj/project.pbxproj" \
      "$_root/deps/ctemplate/build-mac/ctemplate.xcodeproj/project.pbxproj"; do
    if test -f "$_proj" ; then
      perl -0777 -i -pe 's/(PRODUCT_NAME = "ctemplate-ios";)\n\t\t\t\tSDKROOT = iphoneos;/$1/g' "$_proj"
    fi
  done
  if test -f "$_root/build-mac/dependencies/prepare-cyrus-sasl.sh" ; then
    _sasl="$_root/build-mac/dependencies/prepare-cyrus-sasl.sh"
    sed -i '' 's/| grep iphoneos | sed /| grep iphoneos | head -n 1 | sed /' "$_sasl"
    sed -i '' 's/MARCHS="armv7 armv7s arm64"/MARCHS="arm64"/' "$_sasl"
    sed -i '' 's/MARCHS="i386 x86_64 arm64"/MARCHS="x86_64 arm64"/' "$_sasl"
    sed -i '' 's/ARCH=i386/ARCH=x86_64/' "$_sasl"
    perl -i -pe 's/(?<!LC_ALL=C )tr A-Z a-z/LC_ALL=C tr A-Z a-z/' "$_sasl"
    sed -i '' 's|export PATH=/usr/bin:/bin:/usr/sbin:/sbin|export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin|' "$_sasl"
  fi
  if test -f "$_root/src/low-level/imf/mailimf.c" ; then
    perl -0777 -i -pe 's/(else if \(r != MAILIMF_ERROR_PARSE\) \{\s*res = r;\s*goto free_gstr;\s*\})\s*\}/$1\n    else {\n      break;\n    }\n  }/' "$_root/src/low-level/imf/mailimf.c"
  fi
}

build_libsasl_from_libetpan()
{
  _root="$1"
  if test ! -f "$_root/build-mac/dependencies/prepare-cyrus-sasl.sh" ; then
    return 0
  fi
  patch_dep_sources "$_root"
  echo "--- Building libsasl-ios from libetpan deps ---"
  _saved_dir="$(pwd)"
  cd "$_root/build-mac/dependencies"
  sh prepare-cyrus-sasl.sh
  if test x$? != x0 ; then
    echo "Failed to build libsasl-ios"
    exit 1
  fi
  cd "$_saved_dir"
  if test -d "$_root/build-mac/libsasl-ios" ; then
    mkdir -p "$scriptpath/../Externals"
    rm -rf "$scriptpath/../Externals/libsasl-ios"
    cp -R "$_root/build-mac/libsasl-ios" "$scriptpath/../Externals/libsasl-ios"
  fi
}

stamp_externals_built_from_source()
{
  _stamp="$scriptpath/../Externals/.built-from-local-source"
  mkdir -p "$scriptpath/../Externals"
  {
    echo "source=deps"
    echo "built_at=`date -u +%Y-%m-%dT%H:%M:%SZ`"
    for _pair in ctemplate:deps/ctemplate libetpan:deps/libetpan tidy-html5:deps/tidy-html5 ; do
      _pkg="${_pair%%:*}"
      _dir="$scriptpath/../${_pair#*:}"
      if test -d "$_dir/.git" ; then
        echo "$_pkg=`git -C "$_dir" rev-parse HEAD 2>/dev/null || echo unknown`"
      fi
    done
  } > "$_stamp"
}

# Build all iOS Externals from deps/* — never download etpan prebuilt zips.
build_ios_externals_from_local_source()
{
  echo "==> Building Externals from local deps/* (not prebuilt) ..."
  MAILCORE_NO_PREBUILT_DEPS=1
  export MAILCORE_NO_PREBUILT_DEPS

  for _dep in ctemplate-ios libetpan-ios tidy-html5-ios libsasl-ios ; do
    rm -rf "$scriptpath/../Externals/$_dep"
  done
  rm -f "$scriptpath/../Externals/.built-from-local-source"
  rm -f "$scriptpath/../scripts/installed-deps-versions.plist"

  _libetpan="$scriptpath/../deps/libetpan"
  if test ! -d "$_libetpan/build-mac" ; then
    echo "ERROR: missing $_libetpan"
    exit 1
  fi
  build_libsasl_from_libetpan "$_libetpan"

  for _dep in ctemplate-ios libetpan-ios tidy-html5-ios ; do
    _src="$(local_dep_src_dir "$_dep")"
    if test ! -d "$_src/build-mac" ; then
      echo "ERROR: missing local source for $_dep at $_src"
      exit 1
    fi
    echo "--- Building $_dep from $_src ---"
    build_for_external=1 sh "$scriptpath/build-$_dep.sh"
    if test x$? != x0 ; then
      echo "Failed to build $_dep"
      exit 1
    fi
    if test ! -d "$scriptpath/../Externals/$_dep" ; then
      echo "ERROR: Externals/$_dep missing after build"
      exit 1
    fi
  done

  fix_tidy_include_layout "$scriptpath/../Externals/tidy-html5-ios" "$scriptpath/../deps/tidy-html5"
  stamp_externals_built_from_source
  echo "==> Externals ready (built from deps/, see Externals/.built-from-local-source)"
}

build_embedded_ios_deps_from_source()
{
  _libetpan="$(local_dep_src_dir libetpan-ios)"
  if test -d "$_libetpan" ; then
    build_libsasl_from_libetpan "$_libetpan"
  fi
  for _dep in $embedded_deps ; do
    _src="$(local_dep_src_dir "$_dep")"
    if test ! -d "$_src/build-mac" ; then
      echo "Skipping $_dep (no local source tree under deps/)"
      continue
    fi
    echo "--- Building $_dep from local source: $_src ---"
    build_for_external=1 sh "$scriptpath/build-$_dep.sh"
    if test x$? != x0 ; then
      echo "Failed to build $_dep"
      exit 1
    fi
    if test ! -d "$scriptpath/../Externals/$_dep" ; then
      echo "ERROR: $_dep was not installed under Externals/"
      exit 1
    fi
  done
}

copy_embedded_deps_to_mailcore()
{
  _mailcore="$srcdir/$name"
  mkdir -p "$_mailcore/Externals"
  for _dep in $embedded_deps libsasl-ios ; do
    if test ! -d "$scriptpath/../Externals/$_dep" ; then
      echo "Missing built dependency $_dep"
      exit 1
    fi
    echo "Installing $_dep into MailCore Externals"
    rm -rf "$_mailcore/Externals/$_dep"
    cp -R "$scriptpath/../Externals/$_dep" "$_mailcore/Externals/$_dep"
    if test "$_dep" = "tidy-html5-ios" ; then
      fix_tidy_include_layout "$_mailcore/Externals/tidy-html5-ios" "$(local_dep_src_dir tidy-html5-ios)"
    fi
    for _fatlib in "$_mailcore/Externals/$_dep/lib/"*.a ; do
      if test -f "$_fatlib" ; then
        echo "  Removing stale fat library: $(basename "$_fatlib")"
        rm -f "$_fatlib"
      fi
    done
  done
}

build_git_ios()
{
  if test "x$name" = x ; then
    return
  fi

  simarchs="arm64 x86_64"
  sdkminversion="12.0"
  sdkversion="`xcodebuild -showsdks 2>/dev/null | grep iphoneos | head -n 1 | sed -E 's/.*iphoneos(.*)/\1/'`"
  devicearchs="arm64"

  versions_path="$scriptpath/deps-versions.plist"
  version="`defaults read "$versions_path" "$name" 2>/dev/null`"
  version="$(($version+1))"
  if test x$build_for_external = x1 ; then
    version=0
  fi

  if test x$build_for_external = x1 ; then
    builddir="$scriptpath/../Externals/tmp/dependencies"
  else
    builddir="$HOME/MailCore-Builds/dependencies"
  fi
  BUILD_TIMESTAMP=`date +'%Y%m%d%H%M%S'`
  tempbuilddir="$builddir/workdir/$BUILD_TIMESTAMP"
  mkdir -p "$tempbuilddir"
  srcdir="$tempbuilddir/src"
  logdir="$tempbuilddir/log"
  resultdir="$builddir/builds"
  tmpdir="$tempbuilddir/tmp"

  echo "working in $tempbuilddir"

  mkdir -p "$resultdir"
  mkdir -p "$logdir"
  mkdir -p "$tmpdir"
  mkdir -p "$srcdir"

  pushd . >/dev/null

  dep_root=""
  if test x$build_for_external = x1 ; then
    _local_src="$(local_dep_src_dir "$name")"
    if test ! -d "$_local_src/build-mac" ; then
      echo "ERROR: build_for_external requires local source at $_local_src"
      exit 1
    fi
    dep_root="$_local_src"
    echo "Using local source tree for $name: $dep_root"
    patch_dep_sources "$dep_root"
    if test "$name" = "libetpan-ios" ; then
      build_libsasl_from_libetpan "$dep_root"
    fi
  else
    _local_main="$(local_dep_src_dir "$name")"
    if test -z "$_local_main" || test ! -d "$_local_main/build-mac" ; then
      if test "x$url" != x ; then
        mkdir -p "$builddir/downloads"
        pushd "$builddir/downloads" >/dev/null
        if test -d "$name" ; then
          cd "$name"
          git checkout master
          git pull --rebase
        else
          git clone $url "$name"
          cd "$name"
        fi
        popd >/dev/null
      fi
    fi

    if test "x$embedded_deps" != "x" ; then
      build_embedded_ios_deps_from_source
    fi

    _local_src="$(local_dep_src_dir "$name")"
    if test -n "$_local_src" && test -d "$_local_src/build-mac" ; then
      dep_root="$_local_src"
      echo "Using local source tree for $name: $dep_root"
      patch_dep_sources "$dep_root"
    else
      cp -R "$builddir/downloads/$name" "$srcdir/$name"
      dep_root="$srcdir/$name"
      cd "$dep_root"
      if test "x$branch" != x ; then
        if ! git checkout -b "$branch" "origin/$branch" ; then
          git checkout "$branch"
        fi
      fi
      git checkout -q $rev
      patch_dep_sources "$dep_root"
    fi
    echo building $name $version - $rev

    if test "$name" = "libetpan-ios" ; then
      build_libsasl_from_libetpan "$dep_root"
    fi

    if test "x$embedded_deps" != "x" ; then
      copy_embedded_deps_to_mailcore
    fi
  fi
  echo building $name $version - $rev

  BITCODE_FLAGS="-fembed-bitcode"
  if test "x$NOBITCODE" != x ; then
     BITCODE_FLAGS=""
     XCODE_BITCODE_FLAGS="ENABLE_BITCODE=NO"
  fi
  XCTOOL_OTHERFLAGS='$(inherited)'
  XCTOOL_OTHERFLAGS="$XCTOOL_OTHERFLAGS $BITCODE_FLAGS"
  cd "$dep_root/build-mac"
  sdk="iphoneos$sdkversion"
  objroot="$tmpdir/obj/iphoneos"
  echo building $sdk
  xcodebuild -project "$xcode_project" -sdk $sdk -scheme "$xcode_target" -configuration Release SYMROOT="$tmpdir/bin" OBJROOT="$objroot" ARCHS="$devicearchs" IPHONEOS_DEPLOYMENT_TARGET="$sdkminversion" ALWAYS_SEARCH_USER_PATHS=NO OTHER_CFLAGS="$XCTOOL_OTHERFLAGS" $XCODE_BITCODE_FLAGS
  if test x$? != x0 ; then
    echo failed
    exit 1
  fi
  sdk="iphonesimulator$sdkversion"
  objroot="$tmpdir/obj/iphonesimulator"
  echo building $sdk
  xcodebuild -project "$xcode_project" -sdk $sdk -scheme "$xcode_target" -configuration Release SYMROOT="$tmpdir/bin" OBJROOT="$objroot" ARCHS="$simarchs" IPHONEOS_DEPLOYMENT_TARGET="$sdkminversion" ALWAYS_SEARCH_USER_PATHS=NO OTHER_CFLAGS='$(inherited)'
  if test x$? != x0 ; then
    echo failed
    exit 1
  fi
  echo finished

  if echo $library|grep '\.framework$'>/dev/null ; then
    cd "$tmpdir/bin"
    xcframework_name=$(basename "$library" .framework).xcframework
    xcodebuild -create-xcframework -framework Release-iphoneos/$library -framework Release-iphonesimulator/$library -output $xcframework_name
    if test x$? != x0 ; then
      echo failed
      exit 1
    fi
    defaults write "$tmpdir/bin/$xcframework_name/Info.plist" "git-rev" "$rev"
    _xc_output=""
    if test "x$xcframework_output" != x ; then
      _xc_output="$xcframework_output"
    elif test "$name" = "mailcore2-framework-ios" ; then
      _xc_output="$scriptpath/../bin/MailCore.xcframework"
    fi
    if test -n "$_xc_output" ; then
      rm -rf "$_xc_output"
      cp -R "$xcframework_name" "$_xc_output"
      echo "Installed $xcframework_name -> $_xc_output"
    fi
    mkdir -p "$resultdir/$name"
    zip -qry "$resultdir/$name/$name-$version.zip" "$xcframework_name"
    rm -rf "$xcframework_name"
  else
    cd "$tmpdir/bin"
    mkdir -p "$name-$version/$name"
    mkdir -p "$name-$version/$name/lib"
    mkdir -p "$name-$version/$name/lib/iphoneos"
    mkdir -p "$name-$version/$name/lib/iphonesimulator"
    cp "Release-iphoneos/$library" "$name-$version/$name/lib/iphoneos/$library"
    cp "Release-iphonesimulator/$library" "$name-$version/$name/lib/iphonesimulator/$library"
    if test x$build_mailcore = x1 ; then
      mkdir -p "$name-$version/$name/include"
      mv Release-iphoneos/include/MailCore "$name-$version/$name/include"
    else
      mv Release-iphoneos/include "$name-$version/$name"
    fi
    if test "$name" = "tidy-html5-ios" ; then
      fix_tidy_include_layout "$name-$version/$name" "$dep_root"
    fi
    # Do not lipo-merge device and simulator libs: both may contain arm64 for
    # different platforms, which produces an invalid archive on Apple Silicon.
    for dep in $embedded_deps ; do
      if test -d "$dep_root/build-mac/$dep" ; then
        mv "$dep_root/build-mac/$dep" "$name-$version"
      elif test -d "$srcdir/$name/Externals/$dep" ; then
        mv "$srcdir/$name/Externals/$dep" "$name-$version"
      else
        echo Dependency $dep not found
      fi
      if test x$build_mailcore = x1 ; then
        cp -R "$name-$version/$dep/lib" "$name-$version/$name"
        rm -rf "$name-$version/$dep"
      fi
    done
    if test x$build_mailcore = x1 ; then
      mv "$name-$version/$name/lib" "$name-$version"
      mv "$name-$version/$name/include" "$name-$version"
      rm -rf "$name-$version/$name"
      libtool -static -o "$name-$version/$library" "$name-$version/lib"/*.a
      rm -rf "$name-$version/lib"
      mkdir -p "$name-$version/lib"
      mv "$name-$version/$library" "$name-$version/lib"
    fi
    echo "$rev"> "$name-$version/git-rev"
    if test x$build_for_external = x1 ; then
      mkdir -p "$scriptpath/../Externals/$name"
      cp -R "$name-$version/$name/"* "$scriptpath/../Externals/$name/"
      if test "$name" = "tidy-html5-ios" ; then
        fix_tidy_include_layout "$scriptpath/../Externals/$name" "$dep_root"
      fi
      rm -f "$scriptpath/../Externals/$name/git-rev"
      stamp_externals_built_from_source
    else
      mkdir -p "$resultdir/$name"
      zip -qry "$resultdir/$name/$name-$version.zip" "$name-$version"
    fi
  fi

  echo build of $name-$version done

  popd >/dev/null

  echo cleaning
  rm -rf "$tempbuilddir"

  if test x$build_for_external != x1 ; then
    defaults write "$versions_path" "$name" "$version"
    plutil -convert xml1 "$versions_path"
  fi
}

build_git_osx()
{
  sdk="`xcodebuild -showsdks 2>/dev/null | grep macosx | head -n 1 | sed 's/.*macosx\(.*\)/\1/'`"
  archs="x86_64"
  sdkminversion="10.7"
  
  if test "x$name" = x ; then
    return
  fi
  
  versions_path="$scriptpath/deps-versions.plist"
  version="`defaults read "$versions_path" "$name" 2>/dev/null`"
  version="$(($version+1))"
  if test x$build_for_external = x1 ; then
    version=0
  fi

  if test x$build_for_external = x1 ; then
    builddir="$scriptpath/../Externals/tmp/dependencies"
  else
    builddir="$HOME/MailCore-Builds/dependencies"
  fi
  BUILD_TIMESTAMP=`date +'%Y%m%d%H%M%S'`
  tempbuilddir="$builddir/workdir/$BUILD_TIMESTAMP"
  mkdir -p "$tempbuilddir"
  srcdir="$tempbuilddir/src"
  logdir="$tempbuilddir/log"
  resultdir="$builddir/builds"
  tmpdir="$tempbuilddir/tmp"

  echo "working in $tempbuilddir"

  mkdir -p "$resultdir"
  mkdir -p "$logdir"
  mkdir -p "$tmpdir"
  mkdir -p "$srcdir"

  pushd . >/dev/null
  mkdir -p "$builddir/downloads"
  cd "$builddir/downloads"
  if test -d "$name" ; then
  	cd "$name"
    git checkout master
  	git pull --rebase
  else
  	git clone $url "$name"
  	cd "$name"
  fi
  #version=`echo $rev | cut -c1-10`

  popd >/dev/null

  pushd . >/dev/null

  cp -R "$builddir/downloads/$name" "$srcdir/$name"
  cd "$srcdir/$name"
  if test "x$branch" != x ; then
    if ! git checkout -b "$branch" "origin/$branch" ; then
      git checkout "$branch"
    fi
  fi
  git checkout -q $rev
  echo building $name $version - $rev

  cd "$srcdir/$name/build-mac"
  xcodebuild -project "$xcode_project" -sdk macosx$sdk -scheme "$xcode_target" -configuration Release ARCHS="$archs" SYMROOT="$tmpdir/bin" OBJROOT="$tmpdir/obj" MACOSX_DEPLOYMENT_TARGET="$sdkminversion"
  if test x$? != x0 ; then
    echo failed
    exit 1
  fi
  echo finished
  
  if echo $library|grep '\.framework$'>/dev/null ; then
    cd "$tmpdir/bin/Release"
    defaults write "$tmpdir/bin/Release/$library/Resources/Info.plist" "git-rev" "$rev"
    mkdir -p "$resultdir/$name"
    zip -qry "$resultdir/$name/$name-$version.zip" "$library"
  else
    cd "$tmpdir/bin"
    mkdir -p "$name-$version/$name"
    mkdir -p "$name-$version/$name/lib"
    if test x$build_mailcore = x1 ; then
      mkdir -p "$name-$version/$name/include"
      mv Release/include/MailCore "$name-$version/$name/include"
    else
      mv Release/include "$name-$version/$name"
    fi
    mv "Release/$library" "$name-$version/$name/lib"
    for dep in $embedded_deps ; do
      if test -d "$srcdir/$name/build-mac/$dep" ; then
        mv "$srcdir/$name/build-mac/$dep" "$name-$version"
      elif test -d "$srcdir/$name/Externals/$dep" ; then
        mv "$srcdir/$name/Externals/$dep" "$name-$version"
      else
        echo Dependency $dep not found
      fi
      if test x$build_mailcore = x1 ; then
        cp -R "$name-$version/$dep/lib" "$name-$version/$name"
        rm -rf "$name-$version/$dep"
      fi
    done
    if test x$build_mailcore = x1 ; then
      mv "$name-$version/$name/lib" "$name-$version"
      mv "$name-$version/$name/include" "$name-$version"
      rm -rf "$name-$version/$name"
      libtool -static -o "$name-$version/$library" "$name-$version/lib"/*.a
      rm -rf "$name-$version/lib"
      mkdir -p "$name-$version/lib"
      mv "$name-$version/$library" "$name-$version/lib"
    fi
    echo "$rev"> "$name-$version/git-rev"
    if test x$build_for_external = x1 ; then
      mkdir -p "$scriptpath/../Externals/$name"
      cp -R "$name-$version/$name/"* "$scriptpath/../Externals/$name/"
      rm -f "$scriptpath/../Externals/$name/git-rev"
    else
      mkdir -p "$resultdir/$name"
      zip -qry "$resultdir/$name/$name-$version.zip" "$name-$version"
    fi
  fi

  echo build of $name-$version done

  popd >/dev/null

  echo cleaning
  #rm -rf "$tempbuilddir"

  if test x$build_for_external != x1 ; then
    defaults write "$versions_path" "$name" "$version"
    plutil -convert xml1 "$versions_path"
  fi
}

get_prebuilt_dep()
{
  if test "x$MAILCORE_NO_PREBUILT_DEPS" = x1 ; then
    echo "$name: skipping prebuilt download (MAILCORE_NO_PREBUILT_DEPS=1)"
    return 0
  fi

  url="http://d.etpan.org/mailcore2-deps"

  if test "x$name" = x ; then
    return
  fi
  
  versions_path="$scriptpath/deps-versions.plist"
  installed_versions_path="$scriptpath/installed-deps-versions.plist"
  if test ! -f "$versions_path" ; then
    build_for_external=1 "$scriptpath/build-$name.sh"
    return;
  fi
  
  installed_version="`defaults read "$installed_versions_path" "$name" 2>/dev/null`"
  if test ! -d "$scriptpath/../Externals/$name" ; then
    installed_version=
  fi
  if test "x$installed_version" = x ; then
    installed_version="none"
  fi
  version="`defaults read "$versions_path" "$name" 2>/dev/null`"

  echo $name, installed: $installed_version, required: $version
  if test "x$installed_version" = "x$version" ; then
    return
  fi

  BUILD_TIMESTAMP=`date +'%Y%m%d%H%M%S'`
  tempbuilddir="$scriptpath/../Externals/workdir/$BUILD_TIMESTAMP"
  
  mkdir -p "$tempbuilddir"
  cd "$tempbuilddir"
  echo "Downloading $name-$version"
  curl -O "$url/$name/$name-$version.zip"
  unzip -q "$name-$version.zip"
  rm -rf "$scriptpath/../Externals/$name"
  cd "$name-$version"
  for folder in * ; do
      rm -rf "$scriptpath/../Externals/$folder"
      mv "$folder" "$scriptpath/../Externals"
  done
  cd ..
  rm -f "$scriptpath/../Externals/git-rev"
  rm -rf "$tempbuilddir"
  
  if test -d "$scriptpath/../Externals/$name" ; then
    defaults write "$installed_versions_path" "$name" "$version"
    plutil -convert xml1 "$installed_versions_path"
  fi
}
