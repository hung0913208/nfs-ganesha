#!/bin/bash
# File: Prepare.sh
# Description: this file should be run first and it will fetch the latest
# LibBase before use this library to build a new Pipeline

ROOT="$(git rev-parse --show-toplevel)"
BASE="$ROOT/src/Base"
CMAKED="$ROOT/src/CMakeD"

function clean() {
	source "$BASE/Tests/Pipeline/Libraries/Logcat.sh"
	source "$BASE/Tests/Pipeline/Libraries/Package.sh"

	$SU rm -fr $BASE
	$SU rm -fr $ROOT/build
	$SU git clean -fdx
	exit 0
}

DRYRUN=0

while [[ $# -gt 0 ]]; do
	case $1 in
		--verbose)	VERBOSE=1;;
		--dry-run)	DRYRUN=1;;
		--clean)	clean;;
		(--)		shift; break;;
		(*)		if [[ ${#SUBPROJECT} -eq 0 ]]; then SUBPROJECT=$1; else exit -1; fi;;
	esac
	shift
done

if [ ! -d $BASE ]; then
	if ! git clone https://github.com/hung0913208/Base $BASE; then
		exit -1
	else
		ln -s $BASE $ROOT/Base
	fi

	if [[ $DRYRUN -eq 0 ]]; then
		if ! git clone https://github.com/dcarp/cmake-d.git $CMAKED; then
			exit -1
		else
			cp -a $CMAKED/cmake-d/* $BASE/CMakeModules/
		fi

		$BASE/Tests/Pipeline/Prepare.sh Unikey
		exit $?
	else
		exit 0
	fi
else
	source "$BASE/Tests/Pipeline/Libraries/Logcat.sh"
	source "$BASE/Tests/Pipeline/Libraries/Package.sh"

	PIPELINE="$(dirname "$0")"
	CURRENT="$(pwd)"
	SCRIPT="$(basename "$0")"

	if [ -d $ROOT/patches ] && [ -f $ROOT/patches/instructs.txt ]; then
		cat $ROOT/patches/instructs.txt | while read DEFINE; do
			SPLITED=($(echo "$DEFINE" | tr ' ' '\n'))
			METHOD="${SPLITED[0]}"
			PATCH="$ROOT/patches/${SPLITED[1]}"
			DEST="$ROOT/${SPLITED[2]}"

			if [ $METHOD = 'patch' ]; then
				if ! patch $DEST $PATCH; then
					warning "can't apply $PATCH to $DEST"
				fi
			elif [ $METHOD = 'cp' ]; then
				if ! cp $PATCH $DEST; then
					warning "can't apply $PATCH to $DEST"
				fi
			fi
		done
	fi

	if [ -f /etc/netconfig ]; then
		info """here is what is written inside /etc/netconfig:

$(cat /etc/netconfig)
"""
	else
		$SU cp $ROOT/tests/pipeline/netconfig /etc/netconfig
	fi

	cat > $ROOT/CMakeLists.txt << EOF
cmake_minimum_required(VERSION 2.6.3)
project(nfs-ganesha C CXX)

add_subdirectory(src)
EOF

	if ! sed -i '/cmake_minimum_required/d' $ROOT/src/CMakeLists.txt; then
		error "can't remove \`cmake_minimum_required\`"
	elif ! sed -i '/project/d' $ROOT/src/CMakeLists.txt; then
		error "can't remove \`project\`"
	elif ! sed -i 's/SEND_ERROR/AUTHOR_WARNING/g' $ROOT/src/cmake/maintainer_mode.cmake; then
		error "can't edit \`SEND_ERROR\` to \`AUTHOR_WARNING\`"
	elif ! sed -i 's/{CMAKE_SOURCE_DIR}\//&src\//' $ROOT/src/CMakeLists.txt; then
		error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of nfs-ganesha"
	elif ! sed -i 's/{CMAKE_BINARY_DIR}\//&src\//' $ROOT/src/CMakeLists.txt; then
		error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of nfs-ganesha"
	elif ! sed -i 's/{PROJECT_SOURCE_DIR}\//&src\//' $ROOT/src/CMakeLists.txt; then
		error "can't add src to line contains \`{PROJECT_SOURCE_DIR}\`"
	elif ! sed -i 's/{PROJECT_BINARY_DIR}\//&\/src\//' $ROOT/src/CMakeLists.txt; then
		error "can't add src to line contains \`{PROJECT_BINARY_DIR}\`"
	elif ! sed -i 's/{PROJECT_SOURCE_DIR}/{CMAKE_SOURCE_DIR}/g' $ROOT/src/CMakeLists.txt; then
		error "can't edit \`{PROJECT_SOURCE_DIR}\` to \`{CMAKE_SOURCE_DIR}\`"
	elif ! sed -i 's/{PROJECT_BINARY_DIR}/{CMAKE_BINARY_DIR}/g' $ROOT/src/CMakeLists.txt; then
		error "can't edit \`{PROJECT_BINARY_DIR}\` to \`{PROJECT_BINARY_DIR}\`"
	fi

	for SUB in $(ls -1c $ROOT/src); do
		if [ ! -f $ROOT/src/$SUB/CMakeLists.txt ]; then
			continue
		elif ! sed -i "s/{CMAKE_SOURCE_DIR}\//&src\/$SUB\//" $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of $SUB"
		elif ! sed -i "s/{CMAKE_BINARY_DIR}\//&src\/$SUB\//" $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of $SUB"
		elif ! sed -i "s/{PROJECT_SOURCE_DIR}/&\/src\/$SUB\//" $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of $SUB"
		elif ! sed -i "s/{PROJECT_BINARY_DIR}/&\/src\/$SUB\//" $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't add src to line contains \`{CMAKE_SOURCE_DIR}\` of $SUB"
		elif ! sed -i 's/{PROJECT_SOURCE_DIR}/{CMAKE_SOURCE_DIR}/g' $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't edit \`{PROJECT_SOURCE_DIR}\` to \`{CMAKE_SOURCE_DIR}\`"
		elif ! sed -i 's/{PROJECT_BINARY_DIR}/{CMAKE_BINARY_DIR}/g' $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't edit \`{PROJECT_BINARY_DIR}\` to \`{PROJECT_BINARY_DIR}\`"
		elif ! sed -i "s/$SUB\/$SUB/$SUB/g" $ROOT/src/$SUB/CMakeLists.txt; then
			error "can't edit \`$SUB\/$SUB\` to \`$SUB\`"
		fi
	done
fi
