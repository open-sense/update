#!/bin/sh

# Copyright (c) 2015-2016 Franco Fichtner <franco@opnsense.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

set -e

if [ "$(id -u)" != "0" ]; then
	echo "Must be root."
	exit 1
fi

MARKER="/usr/local/opnsense/version/opnsense-update"
ORIGIN="/usr/local/etc/pkg/repos/origin.conf"
URL_KEY="^[[:space:]]*url:[[:space:]]*"
WORKPREFIX="/tmp/opnsense-update"
PKG="pkg-static"
VERSION="16.1.9"
ARCH=$(uname -m)

if [ ! -f ${ORIGIN} ]; then
	echo "Missing origin.conf"
	exit 1
fi

INSTALLED_BASE=
if [ -f ${MARKER}.base ]; then
	INSTALLED_BASE=$(cat ${MARKER}.base)
fi

INSTALLED_KERNEL=
if [ -f ${MARKER}.kernel ]; then
	INSTALLED_KERNEL=$(cat ${MARKER}.kernel)
fi

DO_INSECURE=
DO_RELEASE=
DO_FLAVOUR=
DO_MIRROR=
DO_KERNEL=
DO_LOCAL=
DO_FORCE=
DO_BASE=
DO_PKGS=
DO_SKIP=

while getopts bcfikl:m:n:pr:sv OPT; do
	case ${OPT} in
	b)
		DO_BASE="-b"
		;;
	c)
		# -c only ever checks the embedded version string
		if [ "${VERSION}-${ARCH}" = "${INSTALLED_KERNEL}" -a \
		    "${VERSION}-${ARCH}" = "${INSTALLED_BASE}" ]; then
			exit 1
		fi
		exit 0
		;;
	f)
		DO_FORCE="-f"
		;;
	i)
		DO_INSECURE="-i"
		;;
	k)
		DO_KERNEL="-k"
		;;
	l)
		DO_LOCAL="-l ${OPTARG}"
		;;
	m)
		DO_MIRROR="-m ${OPTARG}"
		;;
	n)
		DO_FLAVOUR="-n ${OPTARG}"
		;;
	p)
		DO_PKGS="-p"
		;;
	r)
		DO_RELEASE="-r ${OPTARG}"
		RELEASE=${OPTARG}
		;;
	s)
		DO_SKIP="-s"
		;;
	v)
		echo ${VERSION}-${ARCH}
		exit 0
		;;
	*)
		echo "Usage: opnsense-update [-bcfkpsv] [-m mirror] [-n flavour] [-r release]" >&2
		exit 1
		;;
	esac
done

if [ -z "${DO_KERNEL}${DO_BASE}${DO_PKGS}" ]; then
	# default is enable all
	DO_KERNEL="-k"
	DO_BASE="-b"
	DO_PKGS="-p"
fi

if [ -n "${DO_FLAVOUR}" ]; then
	# replace the package repo name
	sed -i '' '/'"${URL_KEY}"'/s/${ABI}.*/${ABI}\/'"${DO_FLAVOUR#"-n "}"'\",/' ${ORIGIN}
fi

if [ -n "${DO_MIRROR}" ]; then
	# replace the package repo location
	sed -i '' '/'"${URL_KEY}"'/s/pkg\+.*${ABI}/pkg\+'"${DO_MIRROR#"-m "}"'\/${ABI}/' ${ORIGIN}
fi

if [ -n "${DO_SKIP}" ]; then
	# only invoke flavour and mirror replacement
	exit 0
fi

if [ -n "${DO_PKGS}" ]; then
	${PKG} update ${DO_FORCE}
	${PKG} upgrade -y ${DO_FORCE}
	${PKG} autoremove -y
	${PKG} clean -ya
	if [ -n "${DO_BASE}${DO_KERNEL}" ]; then
		# script may have changed, relaunch...
		opnsense-update ${DO_BASE} ${DO_KERNEL} ${DO_LOCAL} \
		    ${DO_FORCE} ${DO_RELEASE} ${DO_MIRROR}
	fi
	# stop here to prevent the second pass
	exit 0
fi

# if no release was selected we use the embedded defaults
if [ -z "${RELEASE}" ]; then
	RELEASE=${VERSION}
fi

if [ -z "${DO_FORCE}" ]; then
	# disable kernel update if up-to-date
	if [ "${RELEASE}-${ARCH}" = "${INSTALLED_KERNEL}" -a \
	    -n "${DO_KERNEL}" ]; then
		DO_KERNEL=
	fi

	# disable base update if up-to-date
	if [ "${RELEASE}-${ARCH}" = "${INSTALLED_BASE}" -a \
	    -n "${DO_BASE}" ]; then
		DO_BASE=
	fi

	# nothing to do
	if [ -z "${DO_KERNEL}${DO_BASE}" ]; then
		echo "Your system is up to date."
		exit 0
	fi
fi

echo "!!!!!!!!!!!!! ATTENTION !!!!!!!!!!!!!!!!!"
echo "! A kernel/base upgrade is in progress. !"
echo "!  Please do not turn off the system.   !"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

MIRROR=$(sed -n 's/'"${URL_KEY}"'\"pkg\+\(.*\)\/${ABI}\/.*/\1/p' ${ORIGIN})

OBSOLETESET=base-${RELEASE}-${ARCH}.obsolete
KERNELSET=kernel-${RELEASE}-${ARCH}.txz
BASESET=base-${RELEASE}-${ARCH}.txz
WORKDIR=${WORKPREFIX}/${$}
KERNELDIR=/boot/kernel

if [ -n "${DO_LOCAL}" ]; then
	WORKDIR=${DO_LOCAL#"-l "}
fi

fetch_set()
{
	STAGE1="fetch -q ${MIRROR}/sets/${1}.sig -o ${WORKDIR}/${1}.sig"
	STAGE2="fetch -q ${MIRROR}/sets/${1} -o ${WORKDIR}/${1}"
	STAGE3="opnsense-verify -q ${WORKDIR}/${1}"

	if [ -n "${DO_LOCAL}" ]; then
		# already fetched, just test
		STAGE1="test -f ${WORKDIR}/${1}.sig"
		STAGE2="test -f ${WORKDIR}/${1}"
	fi

	if [ -n "${DO_INSECURE}" ]; then
		# no signature, no cry
		STAGE1=":"
		STAGE3=":"
	fi

	echo -n "Fetching ${1}... "

	mkdir -p ${WORKDIR} && ${STAGE1} && ${STAGE2} && \
	    ${STAGE3} && echo "ok" && return

	echo "failed"
	exit 1
}

apply_kernel()
{
	echo -n "Applying ${KERNELSET}... "

	rm -rf ${KERNELDIR}.old && \
	    mv ${KERNELDIR} ${KERNELDIR}.old && \
	    tar -C/ -xpf ${WORKDIR}/${KERNELSET} && \
	    kldxref ${KERNELDIR} && \
	    echo "ok" && return

	echo "failed"
	exit 1
}

apply_base()
{
	echo -n "Applying ${BASESET}... "

	# Ideally, we don't do any exlcude magic and simply
	# reapply all the packages on bootup and do another
	# reboot just to be safe...

	chflags -R noschg /bin /sbin /lib /libexec \
	    /usr/bin /usr/sbin /usr/lib && \
	    tar -C/ -xpf ${WORKDIR}/${BASESET} \
	    --exclude="./etc/group" \
	    --exclude="./etc/master.passwd" \
	    --exclude="./etc/passwd" \
	    --exclude="./etc/shells" \
	    --exclude="./etc/ttys" \
	    --exclude="./etc/rc" && \
	    kldxref ${KERNELDIR} && \
	    echo "ok" && return

	echo "failed"
	exit 1
}

apply_obsolete()
{
	echo -n "Applying ${OBSOLETESET}... "

	while read FILE; do
		rm -f ${FILE}
	done < ${WORKDIR}/${OBSOLETESET}

	echo "ok"
}

if [ -n "${DO_KERNEL}" ]; then
	fetch_set ${KERNELSET}
fi

if [ -n "${DO_BASE}" ]; then
	fetch_set ${BASESET}
	fetch_set ${OBSOLETESET}
fi

if [ -n "${DO_KERNEL}" ]; then
	apply_kernel
fi

if [ -n "${DO_BASE}" ]; then
	apply_base
	apply_obsolete
fi

# bootstrap the directory  if needed
mkdir -p $(dirname ${MARKER})
# remove the file previously used
rm -f ${MARKER}

if [ -n "${DO_KERNEL}" ]; then
	echo ${RELEASE}-${ARCH} > ${MARKER}.kernel
fi

if [ -n "${DO_BASE}" ]; then
	echo ${RELEASE}-${ARCH} > ${MARKER}.base
fi

if [ -z "${DO_LOCAL}" ]; then
	rm -rf ${WORKDIR}
fi

echo "Please reboot."
