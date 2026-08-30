#!/usr/bin/env bash
# Stage a self-contained Windows dist/ tree for Recoll GUI + CLI.
# Intended to run inside MSYS2 MINGW64 on GitHub Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build_mingw}"
DIST_DIR="${DIST_DIR:-$ROOT/installer/dist}"
ASSETS_DIR="${ASSETS_DIR:-$ROOT/release-assets}"

VERSION="$(tr -d '[:space:]' < "$ROOT/src/RECOLL-VERSION.txt")"
SHORT_SHA="${SHORT_SHA:-$(echo "${GITHUB_SHA:-local}" | cut -c1-7)}"
ASSET_PREFIX="${ASSET_PREFIX:-recoll-${VERSION}-${SHORT_SHA}-win64}"
# Continuous builds prefer stable asset names so each publish overwrites the previous file.
if [ "${CONTINUOUS_ASSETS:-}" = "1" ]; then
  PORTABLE_NAME="recoll-win64-portable.zip"
  SETUP_BASENAME="recoll-win64-setup.exe"
else
  PORTABLE_NAME="${ASSET_PREFIX}-portable.zip"
  SETUP_BASENAME="${ASSET_PREFIX}-setup.exe"
fi


echo "ROOT=$ROOT"
echo "BUILD_DIR=$BUILD_DIR"
echo "DIST_DIR=$DIST_DIR"
echo "MSYSTEM_PREFIX=${MSYSTEM_PREFIX:-}"
echo "ASSET_PREFIX=$ASSET_PREFIX"

need() { test -f "$1" || { echo "ERROR: missing $1" >&2; exit 1; }; }

need "$BUILD_DIR/recoll.exe"
need "$BUILD_DIR/recollindex.exe"
need "$BUILD_DIR/recollq.exe"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$BUILD_DIR/recoll.exe" "$BUILD_DIR/recollindex.exe" "$BUILD_DIR/recollq.exe" "$DIST_DIR/"
cp "$ROOT/src/desktop/recoll.ico" "$DIST_DIR/"

# Deploy Qt plugins/DLL next to GUI. Include Chinese Qt widget translations.
windeployqt6 --release --translations zh_CN "$DIST_DIR/recoll.exe"

# Help Qt find shipped translations next to the executable on end-user machines.
cat > "$DIST_DIR/qt.conf" <<'EOF'
[Paths]
Prefix = .
Translations = translations
EOF

# Copy MinGW / library deps discovered via ldd (recursive until fixed point).
# IMPORTANT: use ${MSYSTEM_PREFIX}/bin — do NOT prefix with an extra '/', which
# turns into a UNC path under MSYS (//mingw64/...) and silently skips all copies.
is_mingw_dll() {
  case "$1" in
    "${MSYSTEM_PREFIX}"/*|/mingw64/*|*/mingw64/*) return 0 ;;
    *) return 1 ;;
  esac
}

copy_mingw_deps_once() {
  local added=0
  local f dll dest
  # Also scan plugin subdirs created by windeployqt.
  while IFS= read -r -d '' f; do
    while read -r dll; do
      [ -n "$dll" ] || continue
      [ -f "$dll" ] || continue
      if is_mingw_dll "$dll"; then
        dest="$DIST_DIR/$(basename "$dll")"
        if [ ! -f "$dest" ]; then
          cp "$dll" "$dest"
          added=$((added + 1))
          echo "  + $(basename "$dll")"
        fi
      fi
    done < <(ldd "$f" 2>/dev/null | awk '/=>/ {print $3}')
  done < <(find "$DIST_DIR" -type f \( -name '*.exe' -o -name '*.dll' \) -print0)
  echo "$added"
}

echo "Collecting MinGW runtime dependencies via ldd..."
for round in 1 2 3 4 5 6; do
  added="$(copy_mingw_deps_once)"
  echo "round $round: added $added DLLs"
  [ "$added" -eq 0 ] && break
done

# Hard requirements that must be present for CLI/GUI.
for must in \
  libgcc_s_seh-1.dll \
  libstdc++-6.dll \
  libwinpthread-1.dll \
  zlib1.dll \
  Qt6Core.dll \
  Qt6Gui.dll \
  Qt6Widgets.dll \
  platforms/qwindows.dll
do
  need "$DIST_DIR/$must"
done
# Versioned sonames vary across MSYS2 updates.
ls "$DIST_DIR"/libxapian-*.dll >/dev/null
ls "$DIST_DIR"/libxml2*.dll >/dev/null
ls "$DIST_DIR"/libxslt*.dll >/dev/null
ls "$DIST_DIR"/libiconv-*.dll >/dev/null


# Optional but commonly needed transitive libs — copy if present in prefix.
for dll in \
  libiconv-2.dll libsystre-0.dll libtre-5.dll libintl-8.dll \
  liblzma-5.dll libzstd.dll libb2-1.dll \
  libdouble-conversion.dll \
  libicuin78.dll libicuuc78.dll libicudt78.dll \
  libicuin77.dll libicuuc77.dll libicudt77.dll \
  libicuin76.dll libicuuc76.dll libicudt76.dll \
  libpcre2-16-0.dll libpcre2-8-0.dll \
  libmd4c.dll libpng16-16.dll libfreetype-6.dll \
  libbz2-1.dll libbrotlidec.dll libbrotlicommon.dll \
  libharfbuzz-0.dll libgraphite2.dll libglib-2.0-0.dll \
  libpcre2-64-0.dll; do
  src="${MSYSTEM_PREFIX}/bin/$dll"
  if [ -f "$src" ] && [ ! -f "$DIST_DIR/$dll" ]; then
    cp "$src" "$DIST_DIR/"
    echo "  + $dll (optional)"
  fi
done

# Datadir layout expected by path_rclpkgdatadir() on Windows:
#   <exeDir>/share/examples/recoll.conf
# Official Windows builds also ship Share/translations/*.qm
mkdir -p "$DIST_DIR/share/examples" "$DIST_DIR/share/filters" "$DIST_DIR/share/translations"

# Copy example config files into share/examples (not share/sampleconf).
tar -C "$ROOT/src/sampleconf" --dereference -cf - . \
  | tar -C "$DIST_DIR/share/examples" -xf -

# filters/ has git symlinks; dereference for Windows packages.
tar -C "$ROOT/src/filters" --dereference -cf - . \
  | tar -C "$DIST_DIR/share/filters" -xf -
for f in conftree.py rclconfig.py; do
  if [ -f "$ROOT/src/python/recoll/recoll/$f" ]; then
    cp -f "$ROOT/src/python/recoll/recoll/$f" "$DIST_DIR/share/filters/$f"
  fi
done
need "$DIST_DIR/share/filters/conftree.py"
need "$DIST_DIR/share/filters/rclconfig.py"
need "$DIST_DIR/share/examples/recoll.conf"

# Recoll UI translations (built by qt_add_translation into build_mingw/i18n/).
I18N_DIR="$BUILD_DIR/i18n"
if [ ! -d "$I18N_DIR" ]; then
  echo "ERROR: translation dir missing: $I18N_DIR" >&2
  echo "CMake must compile src/qtgui/i18n/*.ts into .qm files." >&2
  exit 1
fi
cp -f "$I18N_DIR"/*.qm "$DIST_DIR/share/translations/"
need "$DIST_DIR/share/translations/recoll_zh_CN.qm"
# Also keep a copy under exeDir/translations for Qt's qt.conf lookup helpers.
mkdir -p "$DIST_DIR/translations"
cp -f "$DIST_DIR/share/translations"/*.qm "$DIST_DIR/translations/" 2>/dev/null || true

echo "Packaged Recoll translations:"
ls -lh "$DIST_DIR/share/translations"/recoll_zh*.qm

mkdir -p "$ASSETS_DIR"
(
  cd "$DIST_DIR"
  zip -r "${ASSETS_DIR}/${PORTABLE_NAME}" .
)

echo "VERSION=$VERSION"
echo "SHORT_SHA=$SHORT_SHA"
echo "ASSET_PREFIX=$ASSET_PREFIX"
echo "PORTABLE_NAME=$PORTABLE_NAME"
echo "SETUP_BASENAME=$SETUP_BASENAME"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "VERSION=$VERSION"
    echo "SHORT_SHA=$SHORT_SHA"
    echo "ASSET_PREFIX=$ASSET_PREFIX"
    echo "PORTABLE_NAME=$PORTABLE_NAME"
    echo "SETUP_BASENAME=$SETUP_BASENAME"
  } >> "$GITHUB_ENV"
fi

echo "Staged portable package:"
ls -lh "${ASSETS_DIR}/${PORTABLE_NAME}"
echo "DLL count: $(find "$DIST_DIR" -name '*.dll' | wc -l)"
