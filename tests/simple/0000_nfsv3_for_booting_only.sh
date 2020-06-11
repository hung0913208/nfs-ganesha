#!/bin/bash

if [[ $# -eq 3 ]]; then
	ROOT="$(git rev-parse --show-toplevel)"
	IDX=$1
	LIVECD=$2

	if [[ $3 -eq 1 ]]; then
		echo """
EXPORT_DEFAULTS
{
	SecType = sys,krb5,krb5i,krb5p;

	# Restrict all exports to NFS v4 unless otherwise specified
	Protocols = 3;
}

LOG {
	# Default log level for all components
	Default_Log_Level = FULL_DEBUG;

	# Where to log
	Facility {
	       name = FILE;
	       destination = \"$ROOT/pxeboot/nfs-ganesha.log\";
	       enable = active;
	}
}
	"""
fi

echo """
EXPORT
{
	Export_Id = $IDX;
	Path = \"$LIVECD\";
	Pseudo = \"/\";
	Tag = exp$IDX;

	# Override the default set in EXPORT_DEFAULTS
	Protocols = 3;
	MaxRead = 65536;
	MaxWrite = 65536;
	PrefRead = 65536;
	PrefWrite = 65536;

	Transports = \"UDP\", \"TCP\";

	# All clients for which there is no CLIENT block that specifies a
	# different Access_Type will have RW access (this would be an unusual
	# specification in the real world since barring a firewall, this
	# export is world readable and writeable).
	Access_Type = RW;

	# FSAL block
	#
	# This is required to indicate which Ganesha File System Abstraction
	# Layer (FSAL) will be used for this export.

	FSAL
	{
		VFS
 		{
 			FSAL_Shared_Library = \"$ROOT/build/libfsalvfs.so\";

			# Logging file
			#Options: \"/var/log/nfs-ganesha.log\" or some other file path
			#         \"SYSLOG\" prints to syslog
			#         \"STDERR\" prints stderr messages to the console that
			#                  started the ganesha process
			#         \"STDOUT\" prints stdout messages to the console that
			#                  started the ganesha process
			LogFile = \"$ROOT/pxeboot/nfs-ganesha.log\";

			# logging level (NIV_FULL_DEBUG, NIV_DEBUG,
			# NIV_EVNMT, NIV_CRIT, NIV_MAJ, NIV_NULL)
	  		DebugLevel = \"NIV_FULL_DEBUG\";

 		}
	}

	# CLIENT blocks
	#
	# An export may optionally have one or more CLIENT blocks. These blocks
	# specify export options for a restricted set of clients. The export
	# permission options specified in the EXPORT block will apply to any
	# client for which there is no applicable CLIENT block.
	#
	# All export permissions options are available, as well as the
	# following:
	#
	# Clients (required)	The list of clients these export permissions
	#			apply to. Clients may be specified by hostname,
	#			ip address, netgroup, CIDR network address,
	#			host name wild card, or simply \"*\" to apply to
	#			all clients.

	CLIENT
	{
		Clients = *;
		Squash = No_Root_Squash;
		Access_Type = RW;
	}
}
	"""
fi
