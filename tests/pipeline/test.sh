#!/bin/bash

PIPELINE="$(dirname "$0" )"
REBOOTED=1
SSHOPTs="-o StrictHostKeyChecking=no"
ROOT="$(git rev-parse --show-toplevel)"

source $PIPELINE/libraries/Logcat.sh
source $PIPELINE/libraries/Package.sh
source $ROOT/.environment

SCRIPT="$(basename "$0")"

function clean() {
	for I in {0..50}; do
		if [[ $INTERACT -eq 1 ]]; then
			info "this log is showed to prevent the ci stop the hanging pipeline"
			sleep 500
		else
			break
		fi
	done

	if [ -f $ROOT/pxeboot/nfsd-console.log ]; then
		info """here is the console log of nfsd ganesha
-------------------------------------------------------------------------------

$(cat $ROOT/pxeboot/nfsd-console.log)
"""
	fi

	if [ -f $ROOT/pxeboot/nfs-ganesha.log ]; then
		info """here is the log from nfs-ganesha
-------------------------------------------------------------------------------

$(cat $ROOT/pxeboot/nfs-ganesha.log)
"""
	fi

	if [ -f $ROOT/pxeboot/atftp-console.log ]; then
		info """here is the console log of atftpd
-------------------------------------------------------------------------------

$(cat $ROOT/pxeboot/atftp-console.log)
"""
	fi

	if [ -f $ROOT/pxeboot/atftp-syslog.log ]; then
		info """here is the log from atftpd
-------------------------------------------------------------------------------

$(cat $ROOT/pxeboot/atftp-syslog.log)
"""
	fi

	$ROOT/Base/Tools/Utilities/coverage.sh $ROOT/build
}

trap clean EXIT
source $ROOT/Base/Tests/Pipeline/Libraries/Logcat.sh

PASSED=1

if ! ps -aux | grep dnsmasq | grep -v grep &> /dev/null; then
	error "there are problems during starting dnsmasq"
fi

if ! ps -aux | grep atftpd | grep -v grep &> /dev/null; then
	error "there are problems during starting atftpd"
fi

if ! ps -aux | grep qemu | grep -v grep &> /dev/null; then
	error "there are problems during starting qemu"
fi

if which qemu-system-x86_64 &> /dev/null; then
	if [[ ${#NGROK} -gt 0 ]]; then
		info "we're opening a tunnel $($ROOT/Base/Tools/Utilities/ngrok.sh ngrok --token $NGROK --port 5901), you can use vnc-client to connect to it"
	fi
fi

for SUITE in $(ls -1c $ROOT/tests); do
	SUITE=$(basename $SUITE)

	if [ $SUITE = 'pipeline' ] || [[ $(ls -1c $ROOT/tests/$SUITE/*.sh | wc -l) -eq 0 ]]; then
		continue
	fi

	for CASE in $(ls -1c $ROOT/tests/$SUITE/*.sh); do
		CASE=$(basename $CASE)
		CASE=${CASE%.*}
		IDX=0

		if ! cp $ROOT/pxeboot/nfs-ganesha.config.${SUITE}.${CASE} $ROOT/pxeboot/nfs-ganesha.config; then
			error "can't generate nfs-ganesha.config of case $SUITE/$CASE"
		elif ! start_nfsd Debug; then
			error "can't restart ganesha.nfsd"
		elif [[ $REBOOTED -eq 0 ]]; then
			sshpass -p "rootroot" ssh $SSHOPTs root@192.168.100.2 -tt 'reboot'
		fi

		for DISTRO in $(ls -1c $ROOT/tests/pipeline/environments); do
			source $ROOT/tests/pipeline/environments/$DISTRO
	
			IDX=$((IDX+1))
			AVALABLE=0
			PASSED=0
	
			for I in {0..10}; do
				if ! sshpass -p "rootroot" ssh $SSHOPTs root@192.168.100.2 -tt exit 0 &> /dev/null; then
					sleep 10
				elif ! sshpass -p "rootroot" ssh $SSHOPTs root@192.168.100.2 -tt "echo '$(username):$(password)' | chpasswd"; then
					error "can't change password account $(username)"
				elif ! sshpass -p "$(password)" ssh $SSHOPTs $(username)@192.168.100.2 -tt exit 0; then
					error "it seems $(username)'s password is set wrong"
				elif ! is_fully_started "192.168.100.2"; then
					sleep 10
				else
					info "machine $DISTRO is available now, going to test our test suites"
					AVAILABLE=1

					if [ -d $ROOT/tests/$ITEM/steps ]; then	
						export SUITE="$ROOT/tests/$SUITE"
						export MACHINE="$DISTRO"
						export ADDRESS="192.168.100.2"

						for STEP in $(ls -1c $SUITE/steps | sort); do
							. $ROOT/tests/$SUITE/steps/$STEP
						done
					fi

					PASSED=1
					break
				fi
			done
	
			if [[ $AVAILABLE -eq 0 ]]; then
				error "it seems the test nodes can't fully start as expected"
			fi

			if [[ $PASSED -eq 0 ]]; then
				warning "there some issue with distro $DISTRO"
			fi
		
	       		if [ -f $ROOT/pxeboot/nfs-ganesha.log ]; then
				info """this is the verbose log of nfs-ganesha:
-------------------------------------------------------------------------------

$(cat $ROOT/pxeboot/nfs-ganesha.log)
"""
				echo > $ROOT/pxeboot/nfs-ganesha.log
			fi

			if [ -f $ROOT/pxeboot/pxelinux.cfg/default.${IDX} ]; then
				if ! cp $ROOT/pxeboot/pxelinux.cfg/default.${IDX} $ROOT/pxeboot/pxelinux.cfg/default; then
					error "can't generate pxelinux.conf/default of distro $DISTRO"
				else
					sshpass -p "rootroot" ssh $SSHOPTs root@192.168.100.2 -tt 'reboot'
				fi
			else
				REBOOTED=0
				break
			fi
		done

		cp $ROOT/pxeboot/pxelinux.cfg/default.0 $ROOT/pxeboot/pxelinux.cfg/default
	done
done

if [[ $PASSED -eq 1 ]]; then
	info "Finish testing nfs-ganesha"
else
	exit -1
fi
