#!/bin/sh

if [ $# -ne 2 ]; then
	echo "usage: print_dts_epilogue.sh <start addr> <end addr>"
	exit 1
fi

START_ADDR=$1
END_ADDR=`python -c "print(hex($1+$2))"`

cat <<EOF
/ {
	spci {
		compatible = "arm,ffa";
		conduit = "smc";
		/* "tx" or "allocate" */
		mem_share_buffer = "tx";
	};
	chosen {
		linux,initrd-start = <$START_ADDR>;
		linux,initrd-end = <$END_ADDR>;
		stdout-path = "serial0:115200n8";
		bootargs =  "cpuidle.off=1";
	};
	hypervisor {
		compatible = "hafnium,hafnium";
		vm1 {
			debug_name = "linux_test";
			kernel_filename = "vmlinuz";
			ramdisk_filename = "initrd.img";
			uuid = <0x0000 0x0 0x0 0x1>;
			messaging_method = <0x2>;
			smc_whitelist_permissive;
		};
	};
};
EOF
