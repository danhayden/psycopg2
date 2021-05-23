#!/bin/bash

# Create manylinux1 wheels for psycopg2
#
# Look at the .github/workflows/packages.yml file for hints about how to use it.

set -euo pipefail
set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PRJDIR="$( cd "${DIR}/../.." && pwd )"

# Build all the available versions, or just the ones specified in PYVERS
if [ ! "${PYVERS:-}" ]; then
    PYVERS="$(ls /opt/python/)"
fi

# Find psycopg version
VERSION=$(grep -e ^PSYCOPG_VERSION "${PRJDIR}/setup.py" | sed "s/.*'\(.*\)'/\1/")
# A gratuitous comment to fix broken vim syntax file: '")
DISTDIR="${PRJDIR}/dist/psycopg2-$VERSION"

# Replace the package name
if [[ "${PACKAGE_NAME:-}" ]]; then
    sed -i "s/^setup(name=\"psycopg2\"/setup(name=\"${PACKAGE_NAME}\"/" \
        "${PRJDIR}/setup.py"
fi

# Build prerequisite libraries
libdir="$PRJDIR/build/libs/$(uname -p)/"
mkdir -p "$libdir"
cd "$libdir"
${DIR}/build_libpq_manylinux1.sh > /dev/null

# Create the wheel packages
for PYVER in $PYVERS; do
    PYBIN="/opt/python/${PYVER}/bin"
    "${PYBIN}/pip" wheel "${PRJDIR}" -w "${PRJDIR}/dist/"
done

# Bundle external shared libraries into the wheels
for WHL in "${PRJDIR}"/dist/*.whl; do
    auditwheel repair "$WHL" -w "$DISTDIR"
done

# Make sure libpq is not in the system
mkdir -p /libpqbak
mv /usr/local/lib/libpq.* /libpqbak

# Install packages and test
cd "${PRJDIR}"
for PYVER in $PYVERS; do
    PYBIN="/opt/python/${PYVER}/bin"
    "${PYBIN}/pip" install ${PACKAGE_NAME} --no-index -f "$DISTDIR"

    # Print psycopg and libpq versions
    "${PYBIN}/python" -c "import psycopg2; print(psycopg2.__version__)"
    "${PYBIN}/python" -c "import psycopg2; print(psycopg2.__libpq_version__)"
    "${PYBIN}/python" -c "import psycopg2; print(psycopg2.extensions.libpq_version())"

    # Fail if we are not using the expected libpq library
    if [[ "${WANT_LIBPQ:-}" ]]; then
        "${PYBIN}/python" -c "import psycopg2, sys; sys.exit(${WANT_LIBPQ} != psycopg2.extensions.libpq_version())"
    fi

    "${PYBIN}/python" -c "import tests; tests.unittest.main(defaultTest='tests.test_suite')"
done

# Restore the libpq packages
mv /libpqbak/* /usr/local/lib/
