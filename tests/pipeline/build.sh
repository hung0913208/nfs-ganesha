#!/bin/bash
# - File: build.sh
# - Description: This bash script will be run right after prepare.sh and it will
# be used to build based on current branch you want to Tests

PIPELINE="$(dirname "$0" )"
source $PIPELINE/libraries/Logcat.sh
source $PIPELINE/libraries/Package.sh

SCRIPT="$(basename "$0")"

if [[ $# -gt 0 ]]; then
	MODE=$2
else
	MODE=0
fi

if [[ $# -gt 2 ]]; then
	NODE=$3
fi

info "You have run on machine ${machine} script ${SCRIPT}"
info "Your current dir now is $(pwd)"

if [ $(which git) ]; then
	# @NOTE: jump to branch's test suite and perform build
	SPEC="Coverage"
	ROOT="$(git rev-parse --show-toplevel)"
	BUILDER=$ROOT/Base/Tools/Builder/build

	if ! $BUILDER --root $ROOT --debug 1 --rebuild 0 --mode 2; then
		error "can't build nfs-ganesha as expected"
	elif ! ln -s $ROOT/build/$SPEC/src/FSAL/FSAL_VFS/vfs/libfsalvfs.so $ROOT/build/libfsalvfs.so; then
		error "can't make a link to $ROOT/build/libfsalvfs.so"
	elif [[ $MODE -eq 1 ]] && [[ ${#NODE} -gt 0 ]]; then
		OTYPE="iso"
		IDX=0

		$SU cat /etc/netconfig

		# @NOTE: fetch the latest release of supported distros so we can
       		# use them to verify our ibus-unikey black build before we deliver
		# this to the marketplace.

		mkdir -p $ROOT/pxeboot/{pxelinux.cfg,rootfs}

		if ! cp /usr/lib/PXELINUX/pxelinux.0 $ROOT/pxeboot; then
			error "can't copy pxelinux.0 to $ROOT/pxeboot"
		elif ! cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32} $ROOT/pxeboot; then
			error "can't copy syslinux to $ROOT/pxeboot"
		fi

		if [ ! -f /.dockerenv ]; then
			$SU systemctl stop dnsmasq
			$SU systemctl stop atftpd
		fi

		for DISTRO in $(ls -1c $ROOT/tests/pipeline/environments); do
			if [ $OTYPE = 'iso' ]; then
				BOOT="livecd/casper"
				INITRD="initrd=rootfs/$DISTRO/$BOOT/initrd"
			else
				BOOT="boot"	
			fi

			mkdir -p $ROOT/pxeboot/rootfs/$DISTRO

			if $ROOT/tools/utilities/generate-customized-livecd-image.sh 	\
					--input-type iso 				\
					--output-type $OTYPE				\
					--no-image					\
					--output $ROOT/pxeboot/rootfs/$DISTRO		\
					--env $ROOT/tests/pipeline/environments/$DISTRO; then
				info "successful generate $DISTRO's ISO image to start a new simulator"
			else
				error "can't build $DISTRO's ISO image"
			fi

			if [ $OTYPE = 'iso' ]; then
				LIVECD="$ROOT/pxeboot/rootfs/$DISTRO/livecd"	
			else
				LIVECD="$ROOT/pxeboot/rootfs/$DISTRO"
			fi

			for SUITE in $(ls -1c $ROOT/tests); do
				SUITE=$(basename $SUITE)

				if [ $SUITE = 'pipeline' ] || [[ $(ls -1c $ROOT/tests/$SUITE/*.sh | wc -l) -eq 0 ]]; then
					continue
				fi

				for CASE in $(ls -1c $ROOT/tests/$SUITE/*.sh); do
					CASE=$(basename $CASE)
					CASE=${CASE%.*}

					if [ ! -f $ROOT/pxeboot/nfs-ganesha.config.${SUITE}.${CASE} ]; then
						if ! bash $ROOT/tests/${SUITE}/${CASE}.sh $IDX $LIVECD 1 >> $ROOT/pxeboot/nfs-ganesha.config.${SUITE}.${CASE}; then
							error "can't generate $SUITE/$CASE"
						fi
					else
						if ! bash $ROOT/tests/${SUITE}/${CASE}.sh $IDX $LIVECD 0 >> $ROOT/pxeboot/nfs-ganesha.config.${SUITE}.${CASE}; then
							error "can't generate $SUITE/$CASE"
						fi
					fi
				
					if [ ! -f $ROOT/pxeboot/nfs-ganesha.config ]; then
						cp $ROOT/pxeboot/nfs-ganesha.config.${SUITE}.${CASE} $ROOT/pxeboot/nfs-ganesha.config
					fi
				done
			done

			if [ ! -f $ROOT/pxeboot/rootfs/$DISTRO/$BOOT/vmlinuz ]; then
				error "can't generate vmlinuz"
			elif [ ! -f $ROOT/pxeboot/rootfs/$DISTRO/$BOOT/initrd ]; then
				error "can't generate initrd"
			fi

			cat > $ROOT/pxeboot/pxelinux.cfg/default.${IDX} << EOF
default install
prompt   1
timeout  1
  
label install
	kernel rootfs/$DISTRO/$BOOT/vmlinuz
	append $INITRD netboot=nfs nfsroot=192.168.100.1:$LIVECD ip=dhcp rw
EOF
			if [ ! -f $ROOT/pxeboot/pxelinux.cfg/default ]; then
				cp $ROOT/pxeboot/pxelinux.cfg/default.${IDX} $ROOT/pxeboot/pxelinux.cfg/default
			fi

			IDX=$((IDX+1))
		done

		# @NOTE: it seems the developer would like to test with a 
		# virtual machine, so we should generate file .environment
		# here to contain approviated variables to control steps to
		# build and test Unikey with our LiveCD collection

		cat > $ROOT/.environment << EOF
source $ROOT/Base/Tests/Pipeline/Libraries/Package.sh
source $ROOT/Base/Tests/Pipeline/Libraries/Logcat.sh
source $ROOT/Base/Tests/Pipeline/Libraries/QEmu.sh

export VNC="rootroot:$NODE"
export RAM="512M"
export KER_FILENAME=""
export RAM_FILENAME=""
export IMG_FILENAME=""
export TIMEOUT="timeout 60"

if lsmod | grep 'kvm-intel\\|kvm-amd' &> /dev/null; then
	export CPU="host"
fi

function snift() {
	return 0
}

function start_nfsd() {
	SPEC=\$1

	screen -ls "nfsd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
	screen -S "nfsd.pid" -c $ROOT/vms/nfsd.conf -dml					\
		$SU $ROOT/build/\$SPEC/src/ganesha.nfsd -F -p $ROOT/pxeboot/nfs-ganesha.pid	\
				 -f $ROOT/pxeboot/nfs-ganesha.config				\
				 -N NIV_FULL_DEBUG
}

function start_dhcpd() {
	IP=\$(get_ip_interface \$1)
	MASK=\$(get_netmask_interface \$1)

	if ! which dnsmasq >& /dev/null; then
		return 1
	else
		info "start dnsmasq to control pxeboot"
	fi

	echo """
logfile $ROOT/pxeboot/nfsd-console.log
logfile flush 1
log on
logtstamp after 1
logtstamp string "[ %t: %Y-%m-%d %c:%s ]\\012"
logtstamp on
"""> $ROOT/vms/nfsd.conf
	screen -ls "nfsd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
	screen -S "nfsd.pid" -c $ROOT/vms/nfsd.conf -dml					\
		$SU $ROOT/build/$SPEC/src/ganesha.nfsd -F -p $ROOT/pxeboot/nfs-ganesha.pid	\
				 -f $ROOT/pxeboot/nfs-ganesha.config				\
				 -N NIV_FULL_DEBUG

	$SU chmod +x $ROOT/pxeboot

	screen -ls "dhcpd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
	screen -ls "atftp.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done

	screen -S "dhcpd.pid" -dm 					\
		$SU dnsmasq --listen-address=192.168.100.1		\
			    --interface=\$1				\
			    --bind-interfaces	 			\
			    --dhcp-boot=pxelinux.0			\
			    --dhcp-range=192.168.100.2,192.168.100.2	\
			    --dhcp-option=3,0.0.0.0			\
			    --dhcp-option=6,0.0.0.0 --dhcp-script \$2

	echo """
logfile $ROOT/pxeboot/atftp-console.log
logfile flush 1
log on
logtstamp after 1
logtstamp string "[ %t: %Y-%m-%d %c:%s ]\\012"
logtstamp on
"""> $ROOT/vms/atftp.conf
	screen -S "atftp.pid" -c $ROOT/vms/atftp.conf -dmL		\
		$SU atftpd --daemon --no-fork $ROOT/pxeboot		\
			   --user root --group root			\
			   --trace --verbose 7				\
			   --logfile $ROOT/pxeboot/atftp-syslog.log
}

function stop_dhcpd() {
	info "stop dnsmasq"

	screen -ls "nfsd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
	screen -ls "dhcpd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
	screen -ls "atftp.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
}

function stop_nfsd() {
	screen -ls "nfsd.pid" | grep -E '\\s+[0-9]+\\.' | awk -F ' ' '{print \$1}' | while read s; do screen -XS \$s quit; done
}
EOF

		$SU chmod -R 755 $ROOT/pxeboot

		info "going to test with virtual machine"
	fi
else
	error "Please install git first"
fi

info "Congratulation, you have passed ${SCRIPT}"
